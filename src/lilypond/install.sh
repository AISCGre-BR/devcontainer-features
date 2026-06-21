#!/bin/sh
# bash is needed for arrays (_BUILD_PKGS_TO_REMOVE).
VERSION="${VERSION:-2.26.0}"
TEXLIVE_FONTS="${TEXLIVEFONTS:-false}"

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

LILYPOND_PREFIX="/opt/lilypond/${VERSION}"
DOWNLOAD_DIR="$(mktemp -d)"
_BUILD_PKGS_TO_REMOVE=()

cleanup() {
    rm -rf "${DOWNLOAD_DIR}"
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

# Install packages, recording only newly-installed ones for later removal.
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
    if [ "${#to_install[@]}" -gt 0 ]; then
        pkg_install "${to_install[@]}"
    fi
}

remove_build_deps() {
    if [ "${#_BUILD_PKGS_TO_REMOVE[@]}" -eq 0 ]; then
        return
    fi
    echo "Removing build-only packages: ${_BUILD_PKGS_TO_REMOVE[*]}"
    pkg_remove "${_BUILD_PKGS_TO_REMOVE[@]}"
    _BUILD_PKGS_TO_REMOVE=()
}

# ---------------------------------------------------------------------------
# Symlink versioned binaries into /usr/local/bin
# ---------------------------------------------------------------------------
setup_path() {
    for bin in "${LILYPOND_PREFIX}/bin"/*; do
        [ -e "${bin}" ] || continue
        local name
        name="$(basename "${bin}")"
        ln -sf "${bin}" "/usr/local/bin/${name}"
    done
}

# ---------------------------------------------------------------------------
# Installation strategies
# ---------------------------------------------------------------------------

# Primary path: official precompiled tarball (x86_64 glibc systems only).
install_from_official() {
    local version="$1"
    local url="https://gitlab.com/lilypond/lilypond/-/releases/v${version}/downloads/lilypond-${version}-linux-x86_64.tar.gz"

    echo "Installing LilyPond ${version} from official precompiled package."
    update_pkg_index
    # Keep fontconfig at runtime; wget/ca-certificates are build-only.
    pkg_install fontconfig
    install_build_deps wget ca-certificates

    echo "Downloading: ${url}"
    wget -qO "${DOWNLOAD_DIR}/lilypond.tar.gz" "${url}"

    mkdir -p "${LILYPOND_PREFIX}"
    tar -xzf "${DOWNLOAD_DIR}/lilypond.tar.gz" \
        --strip-components=1 \
        -C "${LILYPOND_PREFIX}"

    remove_build_deps
    setup_path
}

# Builds LilyPond from source. Used when the official precompiled binary is not
# available (non-x86_64 architecture) or cannot run (Alpine/musl libc).
#
# LilyPond 2.26.x requires Guile 3.0 >= 3.0.7.
# LilyPond 2.24.x accepts Guile 2.2 or 3.0.
# Build time: ~30 minutes on a typical container.
install_from_source() {
    local version="$1"
    local url="https://gitlab.com/lilypond/lilypond/-/archive/v${version}/lilypond-v${version}.tar.gz"
    local arch
    arch="$(uname -m)"

    echo "Building LilyPond ${version} from source (arch: ${arch}). This may take 30+ minutes."
    update_pkg_index

    # Runtime dependencies — kept after the build.
    if is_debian_like; then
        pkg_install \
            guile-3.0 ghostscript python3 perl fontconfig \
            libfreetype6 libcairo2 libpango-1.0-0 libglib2.0-0 libpng16-16
    elif is_redhat_like; then
        pkg_install \
            guile ghostscript python3 perl fontconfig \
            freetype cairo pango glib2 libpng
    elif is_alpine; then
        pkg_install \
            guile ghostscript python3 perl \
            fontconfig freetype cairo pango glib libpng
    fi

    # Build-only dependencies — tracked for removal after the build.
    if is_debian_like; then
        install_build_deps \
            g++ make autoconf automake libtool bison flex pkg-config \
            guile-3.0-dev libfreetype-dev libcairo2-dev libpango1.0-dev \
            libglib2.0-dev libfontconfig1-dev libpng-dev zlib1g-dev \
            libgc-dev gettext wget ca-certificates
    elif is_redhat_like; then
        install_build_deps \
            gcc-c++ make autoconf automake libtool bison flex pkgconf \
            guile-devel freetype-devel cairo-devel pango-devel glib2-devel \
            fontconfig-devel libpng-devel zlib-devel gc-devel \
            gettext wget ca-certificates
    elif is_alpine; then
        install_build_deps \
            g++ make autoconf automake libtool \
            bison flex pkgconf \
            guile-dev freetype-dev cairo-dev pango-dev glib-dev \
            fontconfig-dev libpng-dev zlib-dev gc-dev gettext-dev \
            wget ca-certificates
    fi

    echo "Downloading: ${url}"
    wget -qO "${DOWNLOAD_DIR}/lilypond-src.tar.gz" "${url}"
    mkdir -p "${DOWNLOAD_DIR}/src"
    tar -xzf "${DOWNLOAD_DIR}/lilypond-src.tar.gz" \
        --strip-components=1 \
        -C "${DOWNLOAD_DIR}/src"

    cd "${DOWNLOAD_DIR}/src"
    if [ -x autogen.sh ]; then
        ./autogen.sh --noconfigure
    else
        autoreconf -fi
    fi
    PYTHON=python3 ./configure \
        --prefix="${LILYPOND_PREFIX}" \
        --disable-documentation
    make -j"$(nproc)"
    make install
    cd -

    setup_path
    remove_build_deps
}

# Absolute last resort: distro package manager for unknown OS families.
# The `version` option is ignored.
install_from_distro() {
    local arch
    arch="$(uname -m)"
    echo "Unsupported OS '${OS_ID}' (arch: ${arch}): cannot build from source or use the official binary."
    echo "Falling back to the distribution package manager (version option ignored)." >&2
    update_pkg_index
    pkg_install lilypond
}

# ---------------------------------------------------------------------------
# TeX Live font integration
# ---------------------------------------------------------------------------
configure_texlive_fonts() {
    if [ "${TEXLIVE_FONTS}" != "true" ]; then
        return
    fi

    local tl_fonts_dir
    tl_fonts_dir="$(find /opt/texlive -mindepth 3 -maxdepth 4 -type d \
        -name 'fonts' -path '*/texmf-dist/fonts' 2>/dev/null | head -1)"

    if [ -z "${tl_fonts_dir}" ]; then
        echo "WARNING: TeX Live fonts directory not found under /opt/texlive." >&2
        echo "         Ensure the 'texlive' feature is installed before 'lilypond'." >&2
        return
    fi

    echo "Registering TeX Live fonts with fontconfig: ${tl_fonts_dir}"
    mkdir -p /etc/fonts/conf.d
    cat > /etc/fonts/conf.d/09-texlive-fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>${tl_fonts_dir}/opentype</dir>
  <dir>${tl_fonts_dir}/truetype</dir>
  <dir>${tl_fonts_dir}/type1</dir>
</fontconfig>
EOF
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f
    echo "TeX Live fonts registered."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if ! is_alpine && [ "$(uname -m)" = "x86_64" ]; then
        install_from_official "${VERSION}"
    elif is_debian_like || is_redhat_like || is_alpine; then
        install_from_source "${VERSION}"
    else
        install_from_distro
    fi

    configure_texlive_fonts

    # See texlive feature for why this is needed.
    chmod 1777 /tmp

    echo "LilyPond installation complete."
    lilypond --version | head -1 || true
}

main
