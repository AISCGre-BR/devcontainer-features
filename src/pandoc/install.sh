#!/bin/sh
set -e

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-linux}"
elif [ -f /etc/alpine-release ]; then
    OS_ID="alpine"
else
    OS_ID="linux"
fi

case "${OS_ID}" in
    debian|ubuntu|mint|pop|kali|raspbian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y --no-install-recommends pandoc
        ;;
    rhel|centos|fedora|rocky|almalinux|ol)
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y pandoc
        else
            yum install -y pandoc
        fi
        ;;
    alpine)
        apk update
        apk add --no-cache pandoc
        ;;
    *)
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
        ;;
esac

echo "Pandoc installation complete."
pandoc --version | head -1 || true
