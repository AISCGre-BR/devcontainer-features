#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# ---------------------------------------------------------------------------
# Grammar library installed
# ---------------------------------------------------------------------------
check "gregorio grammar library installed" \
    test -f /usr/local/lib/tree-sitter/grammars/gregorio.so

reportResults
