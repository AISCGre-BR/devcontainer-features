#!/bin/sh
set -e

# Parse devcontainer-features.env manually instead of sourcing it directly.
# Some devcontainer implementations (e.g. Zed) generate the file without
# quoting option values, so sourcing it causes space-separated values to be
# split: the shell treats the first word as a variable prefix and the rest as
# a command to execute, failing with exit 127.
# Reading line-by-line captures the full value (including spaces) correctly.
if [ -f ./devcontainer-features.env ]; then
    while IFS= read -r _line || [ -n "${_line}" ]; do
        _line="${_line#export }"          # strip optional 'export ' prefix
        case "${_line}" in
            '' | \#*) continue ;;         # skip empty lines and comments
        esac
        case "${_line}" in
            *=*)
                _key="${_line%%=*}"
                _val="${_line#*=}"
                case "${_key}" in
                    *[!A-Za-z0-9_]*) continue ;;   # skip invalid identifiers
                esac
                export "${_key}=${_val}"
                ;;
        esac
    done < ./devcontainer-features.env
fi

./install.sh
