#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# ---------------------------------------------------------------------------
# Binary availability
# ---------------------------------------------------------------------------
check "gregorio-lsp binary present" which gregorio-lsp
check "grelint binary present" which grelint
check "grefmt binary present" which grefmt

check "gregorio-lsp --version runs" bash -c "gregorio-lsp --version 2>&1"

# ---------------------------------------------------------------------------
# Rust toolchain removed after build
# ---------------------------------------------------------------------------
check "cargo removed after build" bash -c "! command -v cargo"
check "rustc removed after build" bash -c "! command -v rustc"

reportResults
