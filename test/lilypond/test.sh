#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# ---------------------------------------------------------------------------
# Binary availability
# ---------------------------------------------------------------------------
check "lilypond is in PATH" which lilypond
check "lilypond --version reports LilyPond" \
    bash -c "lilypond --version 2>&1 | grep -i 'LilyPond'"

# ---------------------------------------------------------------------------
# Versioned install prefix (/opt/lilypond/<version>)
# Present when the official binary or source build was used.
# Absent when the distro package manager was used (Alpine without TeX Live).
# ---------------------------------------------------------------------------
INSTALLED_VERSION="$(lilypond --version 2>/dev/null | awk 'NR==1{print $3}')"

if [ -d /opt/lilypond ]; then
    check "versioned prefix /opt/lilypond/${INSTALLED_VERSION} exists" \
        test -d "/opt/lilypond/${INSTALLED_VERSION}"

    check "lilypond symlink resolves into /opt/lilypond" \
        bash -c "readlink -f \"\$(command -v lilypond)\" | grep -qF '/opt/lilypond/'"
fi

# ---------------------------------------------------------------------------
# End-to-end compilation
# Write a minimal score outside of the check call to avoid here-doc escaping
# issues inside bash -c strings.
# ---------------------------------------------------------------------------
_LY_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${_LY_TMPDIR}"' EXIT
# Prints: \version "2.24.0"\n{ c' }\n
# \version "2.24.0" is accepted by both 2.24.x and 2.26.x without warnings.
printf '\\version "2.24.0"\n{ c'"'"' }\n' > "${_LY_TMPDIR}/test.ly"

check "lilypond compiles a minimal score to PDF" \
    bash -c "lilypond --output='${_LY_TMPDIR}/out' '${_LY_TMPDIR}/test.ly' 2>&1 && test -f '${_LY_TMPDIR}/out.pdf'"

# ---------------------------------------------------------------------------
# TeX Live font integration
# In all scenarios in this test suite, the texlive feature is NOT installed.
# Even when texliveFonts=true (install_texlive_fonts_no_texlive scenario), the
# install script should warn and exit cleanly without creating the conf file.
# ---------------------------------------------------------------------------
check "09-texlive-fonts.conf absent when texlive is not installed" \
    bash -c "! test -f /etc/fonts/conf.d/09-texlive-fonts.conf"

# ---------------------------------------------------------------------------
# Build-only packages removed after source build
# Applies to Alpine and to non-x86_64 glibc systems (ARM64, etc.).
# On x86_64 the official binary is used, so these tools are never installed.
# ---------------------------------------------------------------------------
if [ -f /etc/alpine-release ] || [ "$(uname -m)" != "x86_64" ]; then
    check "g++ removed after build" bash -c "! command -v g++"
    check "bison removed after build" bash -c "! command -v bison"
    check "flex removed after build" bash -c "! command -v flex"
    check "autoconf removed after build" bash -c "! command -v autoconf"
fi

reportResults
