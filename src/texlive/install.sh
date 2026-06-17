#!/bin/sh
# bash is required for array-based Perl module tracking.
# Alpine's /bin/sh (busybox ash) lacks bash arrays, so bootstrap bash first.
SCHEME="${SCHEME:-full}"
# Normalise: accept space- or comma-separated package lists.
PACKAGES="$(printf '%s' "${PACKAGES:-}" | tr ',' ' ')"
RELEASE="${RELEASE:-latest}"
MIRROR="${MIRROR:-}"

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

INSTALL_TL_DIR="$(mktemp -d)"
TEXLIVE_PREFIX="/opt/texlive"

cleanup() {
    rm -rf "${INSTALL_TL_DIR}"
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

update_pkg_index() {
    if is_debian_like; then
        apt-get update -y
    elif is_redhat_like; then
        : # dnf/yum resolve on install
    elif is_alpine; then
        apk update
    fi
}

# ---------------------------------------------------------------------------
# Install OS prerequisites
# ---------------------------------------------------------------------------
install_prerequisites() {
    echo "Installing prerequisites for OS: ${OS_ID}"
    update_pkg_index

    if is_debian_like; then
        pkg_install \
            wget curl ca-certificates fontconfig gnupg \
            perl perl-base \
            libyaml-tiny-perl \
            libfile-homedir-perl \
            libunicode-linebreak-perl \
            liblog-dispatch-perl \
            liblog-log4perl-perl \
            libfile-which-perl \
            libsub-identify-perl
    elif is_redhat_like; then
        pkg_install \
            wget curl ca-certificates fontconfig gnupg2 \
            perl \
            perl-YAML-Tiny \
            perl-File-HomeDir \
            perl-Unicode-LineBreak \
            perl-Log-Dispatch \
            perl-Log-Log4perl \
            perl-File-Which \
            perl-Sub-Identify
    elif is_alpine; then
        pkg_install \
            wget curl ca-certificates fontconfig gnupg \
            perl \
            perl-yaml-tiny \
            perl-file-homedir \
            perl-unicode-linebreak \
            perl-log-dispatch \
            perl-log-log4perl \
            perl-file-which \
            perl-sub-identify
    fi
}

# ---------------------------------------------------------------------------
# Resolve installer URL
# ---------------------------------------------------------------------------
resolve_installer_url() {
    if [ -n "${MIRROR}" ]; then
        echo "${MIRROR%/}/CTAN/systems/texlive/tlnet/install-tl-unx.tar.gz"
        return
    fi

    if [ "${RELEASE}" = "latest" ]; then
        echo "https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"
    else
        echo "https://ftp.tug.org/texlive/historic/${RELEASE}/install-tl-unx.tar.gz"
    fi
}

# ---------------------------------------------------------------------------
# Resolve tlnet repository URL (used by tlmgr after install)
# ---------------------------------------------------------------------------
resolve_tlnet_url() {
    if [ -n "${MIRROR}" ]; then
        echo "${MIRROR%/}/CTAN/systems/texlive/tlnet"
        return
    fi

    if [ "${RELEASE}" = "latest" ]; then
        echo "https://mirror.ctan.org/systems/texlive/tlnet"
    else
        echo "https://ftp.tug.org/texlive/historic/${RELEASE}/tlnet"
    fi
}

# ---------------------------------------------------------------------------
# Download and extract installer
# ---------------------------------------------------------------------------
download_installer() {
    local url="$1"
    echo "Downloading TeX Live installer from: ${url}"
    wget -qO "${INSTALL_TL_DIR}/install-tl-unx.tar.gz" "${url}"
    tar -xzf "${INSTALL_TL_DIR}/install-tl-unx.tar.gz" \
        --strip-components=1 \
        -C "${INSTALL_TL_DIR}"
}

# ---------------------------------------------------------------------------
# Build install profile
# ---------------------------------------------------------------------------
write_profile() {
    local texdir="$1"
    local repo_url="$2"

    cat > "${INSTALL_TL_DIR}/texlive.profile" <<EOF
selected_scheme scheme-${SCHEME}
TEXDIR ${texdir}
TEXMFLOCAL ${TEXLIVE_PREFIX}/texmf-local
TEXMFSYSVAR ${texdir}/texmf-var
TEXMFSYSCONFIG ${texdir}/texmf-config
TEXMFVAR ~/.texlive/texmf-var
TEXMFCONFIG ~/.texlive/texmf-config
TEXMFHOME ~/texmf
instopt_adjustpath 0
instopt_adjustrepo 1
instopt_letter 0
instopt_portable 0
instopt_write18_restricted 1
tlpdbopt_autobackup 0
tlpdbopt_create_formats 1
tlpdbopt_install_docfiles 1
tlpdbopt_install_srcfiles 1
tlpdbopt_post_code 1
tlpdbopt_sys_bin /usr/local/bin
tlpdbopt_sys_info /usr/local/share/info
tlpdbopt_sys_man /usr/local/share/man
EOF
}

# ---------------------------------------------------------------------------
# Run the installer
# ---------------------------------------------------------------------------
run_installer() {
    local texdir="$1"
    local repo_url="$2"

    write_profile "${texdir}" "${repo_url}"

    echo "Running TeX Live installer (scheme: ${SCHEME}, release: ${RELEASE})"
    "${INSTALL_TL_DIR}/install-tl" \
        --profile="${INSTALL_TL_DIR}/texlive.profile" \
        --location="${repo_url}" \
        --no-interaction
}

# ---------------------------------------------------------------------------
# Detect installed bin path and symlink to /usr/local/bin
# ---------------------------------------------------------------------------
setup_path() {
    local texdir="$1"
    local bin_dir
    bin_dir="$(find "${texdir}/bin" -mindepth 1 -maxdepth 1 -type d | head -1)"

    if [ -z "${bin_dir}" ]; then
        echo "WARNING: could not locate TeX Live bin directory under ${texdir}/bin" >&2
        return
    fi

    echo "Linking TeX Live binaries from ${bin_dir} to /usr/local/bin"
    for bin in "${bin_dir}"/*; do
        local name
        name="$(basename "${bin}")"
        if [ ! -e "/usr/local/bin/${name}" ]; then
            ln -s "${bin}" "/usr/local/bin/${name}"
        fi
    done

    # Stable symlink for environment variables
    ln -sfn "${bin_dir}" "${TEXLIVE_PREFIX}/bin"
    local man_dir="${texdir}/texmf-dist/doc/man"
    local info_dir="${texdir}/texmf-dist/doc/info"
    [ -d "${man_dir}" ]  && ln -sfn "${man_dir}"  "${TEXLIVE_PREFIX}/bin/man"
    [ -d "${info_dir}" ] && ln -sfn "${info_dir}" "${TEXLIVE_PREFIX}/bin/info"
}

# ---------------------------------------------------------------------------
# Install extra packages via tlmgr
# ---------------------------------------------------------------------------
install_extra_packages() {
    if [ -z "${PACKAGES}" ]; then
        return
    fi

    echo "Installing additional TeX Live packages: ${PACKAGES}"
    # shellcheck disable=SC2086
    tlmgr install ${PACKAGES}
    # New executables land in bin_dir after tlmgr install; symlink them to sys_bin.
    tlmgr path add
}

# ---------------------------------------------------------------------------
# Verify latexindent Perl dependencies (install via cpanm if missing)
# ---------------------------------------------------------------------------
ensure_latexindent_deps() {
    local missing=()
    local modules=(
        "YAML::Tiny"
        "File::HomeDir"
        "Unicode::GCString"
        "Log::Dispatch"
        "Log::Log4perl"
        "File::Which"
        "Sub::Identify"
    )

    for mod in "${modules[@]}"; do
        if ! perl -M"${mod}" -e 1 &>/dev/null; then
            missing+=("${mod}")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return
    fi

    echo "Installing missing Perl modules for latexindent: ${missing[*]}"

    if command -v cpanm &>/dev/null; then
        cpanm --notest "${missing[@]}"
    else
        # Fallback: install cpanminus then retry
        if is_debian_like; then
            pkg_install cpanminus
        elif is_redhat_like; then
            pkg_install perl-App-cpanminus
        elif is_alpine; then
            pkg_install perl-app-cpanminus
        fi
        cpanm --notest "${missing[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    install_prerequisites

    local installer_url
    installer_url="$(resolve_installer_url)"

    local repo_url
    repo_url="$(resolve_tlnet_url)"

    download_installer "${installer_url}"

    # Determine target directory name
    local texdir_name
    if [ "${RELEASE}" = "latest" ]; then
        # The installer creates a directory named after the actual year; use a
        # wildcard after install to discover it.
        texdir_name="current"
    else
        texdir_name="${RELEASE}"
    fi

    local texdir="${TEXLIVE_PREFIX}/${texdir_name}"

    run_installer "${texdir}" "${repo_url}"

    # If we used "current" as placeholder, discover the real dir
    if [ "${texdir_name}" = "current" ]; then
        local real_dir
        real_dir="$(find "${TEXLIVE_PREFIX}" -mindepth 1 -maxdepth 1 -type d ! -name 'texmf-local' | head -1)"
        if [ -n "${real_dir}" ] && [ "${real_dir}" != "${texdir}" ]; then
            texdir="${real_dir}"
        fi
    fi

    setup_path "${texdir}"

    install_extra_packages
    ensure_latexindent_deps

    echo "TeX Live installation complete."
    tex --version | head -1 || true
}

main
