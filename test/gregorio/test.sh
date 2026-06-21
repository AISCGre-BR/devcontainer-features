#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# The feature script must complete without error regardless of options.
check "feature completed without error" true

# ---------------------------------------------------------------------------
# Gregorio binary checks (only when gregorio_version was set)
# ---------------------------------------------------------------------------
if command -v gregorio &>/dev/null; then
    check "gregorio binary runs" bash -c "gregorio --version 2>&1 | grep -i gregorio"

    # Build-only deps (Autotools + fontforge) must not remain after installation.
    check "fontforge removed after build" bash -c "! command -v fontforge"
    check "bison removed after build" bash -c "! command -v bison"
    check "flex removed after build" bash -c "! command -v flex"
fi

reportResults
