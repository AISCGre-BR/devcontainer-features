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

    # Build-only deps that must not remain in the image after installation.
    check "cmake removed after gregorio build" bash -c "! command -v cmake"
    check "fontforge removed after gregorio build" bash -c "! command -v fontforge"
fi

# ---------------------------------------------------------------------------
# gregorio-lsp checks (only when gregorio_lsp_version was set)
# ---------------------------------------------------------------------------
if command -v gregorio-lsp &>/dev/null; then
    check "gregorio-lsp binary present" which gregorio-lsp
    check "grelint binary present" which grelint
    check "grefmt binary present" which grefmt

    # Rust toolchain must have been removed after the build.
    check "cargo removed after gregorio-lsp build" bash -c "! command -v cargo"
    check "rustc removed after gregorio-lsp build" bash -c "! command -v rustc"
fi

reportResults
