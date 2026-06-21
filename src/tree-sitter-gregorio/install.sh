#!/bin/sh
# bash is required for array-based build-dep tracking.
# Alpine's /bin/sh (busybox ash) lacks bash arrays, so bootstrap bash first.
HOST="${HOST:-github}"
REPOSITORY="${REPOSITORY:-aiscgre-br/tree-sitter-gregorio}"
REF="${REF:-}"

if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        if command -v apk >/dev/null 2>&1; then
            echo "Installing bash (required for build)..."
            apk add --no-cache bash
        else
            echo "ERROR: bash is required but not found." >&2
            exit 1
        fi
    fi
    exec bash "$0" "$@"
fi

# ---- bash only below this line ----
set -euo pipefail

BUILD_DIR="$(mktemp -d)"
_BUILD_PKGS_TO_REMOVE=()

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID:-linux}"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        echo "linux"
    fi
}

OS_ID="$(detect_os)"

is_debian_like() {
    case "${OS_ID}" in
        debian|ubuntu|mint|pop|kali|raspbian) return 0 ;;
        *) return 1 ;;
    esac
}

is_redhat_like() {
    case "${OS_ID}" in
        rhel|centos|fedora|rocky|almalinux|ol) return 0 ;;
        *) return 1 ;;
    esac
}

is_alpine() {
    [ "${OS_ID}" = "alpine" ]
}

# ---------------------------------------------------------------------------
# Package manager helpers
# ---------------------------------------------------------------------------
pkg_install() {
    if is_debian_like; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y --no-install-recommends "$@"
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            dnf install -y "$@"
        else
            yum install -y "$@"
        fi
    elif is_alpine; then
        apk add --no-cache "$@"
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi
}

pkg_remove() {
    if is_debian_like; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y "$@"
        apt-get autoremove -y
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            dnf remove -y "$@"
        else
            yum remove -y "$@"
        fi
    elif is_alpine; then
        apk del "$@"
    fi
}

update_pkg_index() {
    if is_debian_like; then
        apt-get update -y
    elif is_alpine; then
        apk update
    fi
}

is_pkg_installed() {
    local pkg="$1"
    if is_debian_like; then
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"
    elif is_redhat_like; then
        rpm -q "${pkg}" &>/dev/null
    elif is_alpine; then
        apk info -e "${pkg}" &>/dev/null
    else
        return 1
    fi
}

# Install packages, recording only newly-installed ones for removal after build.
install_build_deps() {
    local to_install=()
    for pkg in "$@"; do
        if is_pkg_installed "${pkg}"; then
            echo "  (already present, will not remove later: ${pkg})"
        else
            _BUILD_PKGS_TO_REMOVE+=("${pkg}")
            to_install+=("${pkg}")
        fi
    done
    if [ ${#to_install[@]} -gt 0 ]; then
        pkg_install "${to_install[@]}"
    fi
}

remove_build_deps() {
    if [ ${#_BUILD_PKGS_TO_REMOVE[@]} -eq 0 ]; then
        return
    fi
    echo "Removing build-only packages: ${_BUILD_PKGS_TO_REMOVE[*]}"
    pkg_remove "${_BUILD_PKGS_TO_REMOVE[@]}"
    _BUILD_PKGS_TO_REMOVE=()
}

# ---------------------------------------------------------------------------
# Repository URL construction
# ---------------------------------------------------------------------------
construct_repo_url() {
    local host="$1"
    local repo="$2"

    case "${host}" in
        github)
            echo "https://github.com/${repo}"
            ;;
        gitlab)
            echo "https://gitlab.com/${repo}"
            ;;
        codeberg)
            echo "https://codeberg.org/${repo}"
            ;;
        bitbucket)
            echo "https://bitbucket.org/${repo}"
            ;;
        *)
            echo "Unsupported host: ${host}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Tarball URL construction — ref is passed as-is (branch, tag, commit, or empty for HEAD).
# ---------------------------------------------------------------------------
construct_tarball_url() {
    local host="$1"
    local repo="$2"
    local ref="$3"

    case "${host}" in
        github)
            if [ -z "${ref}" ]; then
                echo "https://github.com/${repo}/archive/HEAD.tar.gz"
            else
                echo "https://github.com/${repo}/archive/${ref}.tar.gz"
            fi
            ;;
        gitlab)
            local repo_name="${repo##*/}"
            local git_ref="${ref:-HEAD}"
            echo "https://gitlab.com/${repo}/-/archive/${git_ref}/${repo_name}-${git_ref}.tar.gz"
            ;;
        codeberg)
            echo "https://codeberg.org/${repo}/archive/${ref:-HEAD}.tar.gz"
            ;;
        bitbucket)
            echo "https://bitbucket.org/${repo}/get/${ref:-HEAD}.tar.gz"
            ;;
        *)
            echo "Unsupported host: ${host}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------
resolve_github_latest() {
    local repo_url="$1"
    local repo
    repo="$(printf '%s' "${repo_url}" | sed 's|https://github.com/||')"
    curl -sSfL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' \
        | head -1 \
        | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

# ---------------------------------------------------------------------------
# Install tree-sitter-gregorio grammar from source
# ---------------------------------------------------------------------------
install_tree_sitter_gregorio() {
    local ref="${REF}"

    local repo_url
    repo_url="$(construct_repo_url "${HOST}" "${REPOSITORY}")"

    echo "Installing prerequisites..."
    update_pkg_index
    pkg_install curl ca-certificates

    # Resolve the ref and tarball URL.
    # Empty ref  → HEAD of the default branch.
    # "latest"   → latest release tag resolved via the forge API.
    # Anything else → used as-is (branch name, tag name, or commit hash).
    local display_ref

    if [ -z "${ref}" ]; then
        display_ref="HEAD"
    elif [ "${ref}" = "latest" ]; then
        echo "Resolving latest tree-sitter-gregorio release..."
        ref="$(resolve_github_latest "${repo_url}")"
        echo "  -> ${ref}"
        display_ref="${ref}"
    else
        display_ref="${ref}"
    fi

    local tarball_url
    tarball_url="$(construct_tarball_url "${HOST}" "${REPOSITORY}" "${ref}")"

    echo "Installing tree-sitter-gregorio build dependencies..."
    # tree-sitter-gregorio commits parser.c so only a C compiler + make are
    # needed to build the .so grammar library. The tree-sitter CLI is only
    # required to regenerate parser.c from grammar.js (not needed here).
    if is_debian_like; then
        install_build_deps build-essential gcc g++ make pkg-config
    elif is_redhat_like; then
        install_build_deps gcc gcc-c++ make pkgconf
    elif is_alpine; then
        install_build_deps build-base gcc g++ make pkgconfig
    fi

    echo "Downloading tree-sitter-gregorio ${display_ref} from ${tarball_url}..."
    curl -sSfL "${tarball_url}" -o "${BUILD_DIR}/tree-sitter-gregorio.tar.gz"

    local src_dir="${BUILD_DIR}/tree-sitter-gregorio-src"
    mkdir -p "${src_dir}"
    tar -xzf "${BUILD_DIR}/tree-sitter-gregorio.tar.gz" --strip-components=1 -C "${src_dir}"

    echo "Building tree-sitter-gregorio grammar..."
    (
        cd "${src_dir}"
        if [ -f Makefile ]; then
            make
        elif [ -f build.sh ]; then
            bash build.sh
        elif [ -f package.json ]; then
            # If it's an npm project, try to use npm
            if command -v npm &>/dev/null; then
                npm install
                npm run build || true
            fi
        fi
    )

    echo "Installing tree-sitter-gregorio grammar..."
    # Tree-sitter grammars are typically installed in ~/.local/share/tree-sitter/grammars
    # or in /usr/local/lib/tree-sitter/grammars
    local grammar_dir="/usr/local/lib/tree-sitter/grammars"
    mkdir -p "${grammar_dir}"

    # Copy compiled grammar library if it exists
    if [ -f "${src_dir}/build/Release/tree-sitter-gregorio.so" ]; then
        install -m 0755 "${src_dir}/build/Release/tree-sitter-gregorio.so" "${grammar_dir}/gregorio.so"
        echo "Installed grammar library to ${grammar_dir}/gregorio.so"
    elif [ -f "${src_dir}/build/tree-sitter-gregorio.so" ]; then
        install -m 0755 "${src_dir}/build/tree-sitter-gregorio.so" "${grammar_dir}/gregorio.so"
        echo "Installed grammar library to ${grammar_dir}/gregorio.so"
    else
        echo "WARNING: compiled grammar library not found" >&2
    fi

    echo "tree-sitter-gregorio ${display_ref} installed."

    echo "Removing tree-sitter-gregorio build dependencies..."
    remove_build_deps
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    install_tree_sitter_gregorio
    echo "Tree-sitter Gregorio feature installation complete."
}

main
