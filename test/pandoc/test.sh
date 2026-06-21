#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# ---------------------------------------------------------------------------
# Binary availability
# ---------------------------------------------------------------------------
check "pandoc is in PATH" which pandoc
check "pandoc --version reports pandoc" \
    bash -c "pandoc --version 2>&1 | grep -i 'pandoc'"

# ---------------------------------------------------------------------------
# End-to-end conversion
# ---------------------------------------------------------------------------
check "pandoc converts Markdown to HTML" \
    bash -c "echo '# Hello' | pandoc -f markdown -t html | grep -qi '<h1'"

check "pandoc converts Markdown to plain text" \
    bash -c "echo '**bold**' | pandoc -f markdown -t plain | grep -q 'bold'"

reportResults
