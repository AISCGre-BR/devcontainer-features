#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

check "lilypond is in PATH" which lilypond
check "lilypond --version reports LilyPond" \
    bash -c "lilypond --version 2>&1 | grep -i 'LilyPond'"

# Assert the source build path was taken (not apk add lilypond).
INSTALLED_VERSION="$(lilypond --version 2>/dev/null | awk 'NR==1{print $3}')"
check "source build prefix /opt/lilypond exists" test -d /opt/lilypond
check "versioned prefix /opt/lilypond/${INSTALLED_VERSION} exists" \
    test -d "/opt/lilypond/${INSTALLED_VERSION}"
check "lilypond symlink resolves into /opt/lilypond" \
    bash -c "readlink -f \"\$(command -v lilypond)\" | grep -qF '/opt/lilypond/'"

_LY_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${_LY_TMPDIR}"' EXIT
printf '\\version "2.24.0"\n{ c'"'"' }\n' > "${_LY_TMPDIR}/test.ly"
check "lilypond compiles a minimal score to PDF" \
    bash -c "lilypond --output='${_LY_TMPDIR}/out' '${_LY_TMPDIR}/test.ly' 2>&1 && test -f '${_LY_TMPDIR}/out.pdf'"

check "g++ removed after build" bash -c "! command -v g++"
check "bison removed after build" bash -c "! command -v bison"
check "flex removed after build" bash -c "! command -v flex"
check "autoconf removed after build" bash -c "! command -v autoconf"

reportResults
