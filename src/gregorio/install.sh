#!/usr/bin/env bash
set -euo pipefail

GREGORIO_VERSION="${GREGORIO_VERSION:-}"
GREGORIO_REPOSITORY="${GREGORIO_REPOSITORY:-https://github.com/gregorio-project/gregorio}"
GREGORIO_LSP_VERSION="${GREGORIO_LSP_VERSION:-}"

GREGORIO_LSP_REPO="https://github.com/aiscgre-br/gregorio-lsp"

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

# Ensure version has a leading 'v' for GitHub tag lookup.
normalize_tag() {
    local version="$1"
    case "${version}" in
        v*) echo "${version}" ;;
        *)  echo "v${version}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Install Gregorio from source
# ---------------------------------------------------------------------------
install_gregorio() {
    local version="${GREGORIO_VERSION}"

    if [ "${version}" = "latest" ]; then
        echo "Resolving latest Gregorio release..."
        version="$(resolve_github_latest "${GREGORIO_REPOSITORY}")"
        echo "  -> ${version}"
    fi

    local tag
    tag="$(normalize_tag "${version}")"

    echo "Installing Gregorio build dependencies..."
    if is_debian_like; then
        update_pkg_index
        install_build_deps cmake gcc g++ make python3 fontforge pkg-config
    elif is_redhat_like; then
        install_build_deps cmake gcc gcc-c++ make python3 fontforge pkgconf
    elif is_alpine; then
        update_pkg_index
        install_build_deps cmake gcc g++ make python3 fontforge pkgconfig
    fi

    local tarball_url="${GREGORIO_REPOSITORY}/archive/refs/tags/${tag}.tar.gz"
    echo "Downloading Gregorio ${tag} from ${tarball_url}..."
    curl -sSfL "${tarball_url}" -o "${BUILD_DIR}/gregorio.tar.gz"

    local src_dir="${BUILD_DIR}/gregorio-src"
    mkdir -p "${src_dir}"
    tar -xzf "${BUILD_DIR}/gregorio.tar.gz" --strip-components=1 -C "${src_dir}"

    local build_dir="${BUILD_DIR}/gregorio-build"
    mkdir -p "${build_dir}"

    echo "Configuring Gregorio..."
    cmake -S "${src_dir}" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local

    echo "Building Gregorio..."
    cmake --build "${build_dir}" --parallel "$(nproc)"

    echo "Installing Gregorio..."
    cmake --install "${build_dir}"

    # Refresh the TeX filename database so TEXMFLOCAL files are found.
    if command -v texhash &>/dev/null; then
        texhash
    elif command -v mktexlsr &>/dev/null; then
        mktexlsr
    fi

    echo "Gregorio ${tag} installed."

    echo "Removing Gregorio build dependencies..."
    remove_build_deps
}

# ---------------------------------------------------------------------------
# Install gregorio-lsp (and grelint, grefmt) from source
# ---------------------------------------------------------------------------
install_gregorio_lsp() {
    local version="${GREGORIO_LSP_VERSION}"

    if [ "${version}" = "latest" ]; then
        echo "Resolving latest gregorio-lsp release..."
        version="$(resolve_github_latest "${GREGORIO_LSP_REPO}")"
        echo "  -> ${version}"
    fi

    local tag
    tag="$(normalize_tag "${version}")"

    echo "Installing Rust build toolchain..."
    if is_debian_like; then
        update_pkg_index
        install_build_deps rustc cargo gcc pkg-config
    elif is_redhat_like; then
        install_build_deps rust cargo gcc pkgconf
    elif is_alpine; then
        update_pkg_index
        install_build_deps rust cargo gcc musl-dev pkgconfig
    fi

    local tarball_url="${GREGORIO_LSP_REPO}/archive/refs/tags/${tag}.tar.gz"
    echo "Downloading gregorio-lsp ${tag} from ${tarball_url}..."
    curl -sSfL "${tarball_url}" -o "${BUILD_DIR}/gregorio-lsp.tar.gz"

    local src_dir="${BUILD_DIR}/gregorio-lsp-src"
    mkdir -p "${src_dir}"
    tar -xzf "${BUILD_DIR}/gregorio-lsp.tar.gz" --strip-components=1 -C "${src_dir}"

    echo "Building gregorio-lsp, grelint, grefmt..."
    # Redirect Cargo's home and cache into the temp build dir so nothing
    # leaks into the container's home directory.
    export CARGO_HOME="${BUILD_DIR}/cargo-home"
    export CARGO_TARGET_DIR="${BUILD_DIR}/cargo-target"

    (
        cd "${src_dir}"
        cargo build --release --locked 2>/dev/null \
            || cargo build --release
    )

    echo "Installing gregorio-lsp binaries to /usr/local/bin..."
    for bin in gregorio-lsp grelint grefmt; do
        if [ -f "${CARGO_TARGET_DIR}/release/${bin}" ]; then
            install -m 0755 "${CARGO_TARGET_DIR}/release/${bin}" "/usr/local/bin/${bin}"
        else
            echo "WARNING: expected binary not found: ${bin}" >&2
        fi
    done

    echo "gregorio-lsp ${tag} installed."

    echo "Removing Rust build toolchain..."
    remove_build_deps
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ -n "${GREGORIO_VERSION}" ]; then
        install_gregorio
    fi

    if [ -n "${GREGORIO_LSP_VERSION}" ]; then
        install_gregorio_lsp
    fi

    if [ -z "${GREGORIO_VERSION}" ] && [ -z "${GREGORIO_LSP_VERSION}" ]; then
        echo "No Gregorio components requested; the version bundled with TeX Live will be used."
    fi

    echo "Gregorio feature installation complete."
}

main
