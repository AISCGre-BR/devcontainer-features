#!/bin/sh
# bash is required for array-based build-dep tracking.
# Alpine's /bin/sh (busybox ash) lacks bash arrays, so bootstrap bash first.
HOST="${HOST:-github}"
REPOSITORY="${REPOSITORY:-gregorio-project/gregorio}"
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
# Install Gregorio from source
# ---------------------------------------------------------------------------
install_gregorio() {
    local ref="${REF}"

    local repo_url
    repo_url="$(construct_repo_url "${HOST}" "${REPOSITORY}")"

    # Resolve the ref and tarball URL.
    # Empty ref  → HEAD of the default branch.
    # "latest"   → latest release tag resolved via the forge API.
    # Anything else → used as-is (branch name, tag name, or commit hash).
    local display_ref

    if [ -z "${ref}" ]; then
        display_ref="HEAD"
    elif [ "${ref}" = "latest" ]; then
        echo "Resolving latest Gregorio release..."
        ref="$(resolve_github_latest "${repo_url}")"
        echo "  -> ${ref}"
        display_ref="${ref}"
    else
        display_ref="${ref}"
    fi

    local tarball_url
    tarball_url="$(construct_tarball_url "${HOST}" "${REPOSITORY}" "${ref}")"

    echo "Installing Gregorio build dependencies..."
    if is_debian_like; then
        update_pkg_index
        install_build_deps autoconf automake libtool gcc make flex bison python3 fontforge pkg-config
    elif is_redhat_like; then
        install_build_deps autoconf automake libtool gcc make flex bison python3 fontforge pkgconf
    elif is_alpine; then
        update_pkg_index
        install_build_deps autoconf automake libtool gcc make flex bison python3 fontforge pkgconfig
    fi

    echo "Downloading Gregorio ${display_ref} from ${tarball_url}..."
    curl -sSfL "${tarball_url}" -o "${BUILD_DIR}/gregorio.tar.gz"

    local src_dir="${BUILD_DIR}/gregorio-src"
    mkdir -p "${src_dir}"
    tar -xzf "${BUILD_DIR}/gregorio.tar.gz" --strip-components=1 -C "${src_dir}"

    (
        cd "${src_dir}"
        echo "Generating autotools build files..."
        autoreconf -fi
        echo "Configuring Gregorio..."
        # Run with bash explicitly: Gregorio's configure uses CFLAGS+= (bash-ism)
        # which breaks under busybox ash (/bin/sh on Alpine).
        bash ./configure --prefix=/usr/local
        echo "Building Gregorio..."
        make -j"$(nproc)"
        echo "Installing Gregorio..."
        make install
    )

    # Refresh the TeX filename database so TEXMFLOCAL files are found.
    if command -v texhash &>/dev/null; then
        texhash
    elif command -v mktexlsr &>/dev/null; then
        mktexlsr
    fi

    echo "Gregorio ${display_ref} installed."

    echo "Removing Gregorio build dependencies..."
    remove_build_deps
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    install_gregorio
    echo "Gregorio feature installation complete."
}

main
