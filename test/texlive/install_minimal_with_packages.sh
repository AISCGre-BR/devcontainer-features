#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

# The minimal scheme provides only tex/pdftex; latex engines (pdflatex etc.)
# are not included. Only verify the toolchain and the requested extra packages.
check "tex version" bash -c "tex --version | grep -i 'TeX'"
check "tlmgr available" which tlmgr
check "latexmk available" which latexmk
check "biber available" which biber

check "latexindent Perl YAML::Tiny" perl -MYAML::Tiny -e 1
check "latexindent Perl File::HomeDir" perl -MFile::HomeDir -e 1
check "latexindent Perl Unicode::GCString" perl -MUnicode::GCString -e 1
check "latexindent Perl Log::Dispatch" perl -MLog::Dispatch -e 1
check "latexindent Perl Log::Log4perl" perl -MLog::Log4perl -e 1
check "latexindent Perl File::Which" perl -MFile::Which -e 1
check "latexindent Perl Sub::Identify" perl -MSub::Identify -e 1

reportResults
