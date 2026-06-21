#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

check "lilypond is in PATH" which lilypond
check "lilypond --version reports LilyPond" \
    bash -c "lilypond --version 2>&1 | grep -i 'LilyPond'"

INSTALLED_VERSION="$(lilypond --version 2>/dev/null | awk 'NR==1{print $3}')"
check "installed version is 2.24.4" [ "${INSTALLED_VERSION}" = "2.24.4" ]
check "versioned prefix /opt/lilypond/2.24.4 exists" \
    test -d "/opt/lilypond/2.24.4"

_LY_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${_LY_TMPDIR}"' EXIT
printf '\\version "2.24.0"\n{ c'"'"' }\n' > "${_LY_TMPDIR}/test.ly"
check "lilypond compiles a minimal score to PDF" \
    bash -c "lilypond --output='${_LY_TMPDIR}/out' '${_LY_TMPDIR}/test.ly' 2>&1 && test -f '${_LY_TMPDIR}/out.pdf'"

reportResults
