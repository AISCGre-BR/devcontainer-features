#!/usr/bin/env bash
set -euo pipefail

source dev-container-features-test-lib

check "tex version" bash -c "tex --version | grep -i 'TeX'"
check "pdflatex available" which pdflatex
check "xelatex available" which xelatex
check "lualatex available" which lualatex
check "latexmk available" which latexmk
check "tlmgr available" which tlmgr

check "latexindent Perl YAML::Tiny" perl -MYAML::Tiny -e 1
check "latexindent Perl File::HomeDir" perl -MFile::HomeDir -e 1
check "latexindent Perl Unicode::GCString" perl -MUnicode::GCString -e 1
check "latexindent Perl Log::Dispatch" perl -MLog::Dispatch -e 1
check "latexindent Perl Log::Log4perl" perl -MLog::Log4perl -e 1
check "latexindent Perl File::Which" perl -MFile::Which -e 1
check "latexindent Perl Sub::Identify" perl -MSub::Identify -e 1

check "latexindent runs" bash -c "
    t=\$(mktemp --suffix=.tex)
    { echo '\\begin{document}'; echo '\\end{document}'; } > \"\${t}\"
    latexindent --logfile=/dev/null \"\${t}\" >/dev/null
"

reportResults
