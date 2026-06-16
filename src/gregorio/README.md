# Gregorio

Installs [Gregorio](https://gregorio-project.github.io/) — the Gregorian chant score engraver — from source on Debian/Ubuntu, Red Hat/Fedora, or Alpine Linux.

Supported base images: Debian/Ubuntu, Red Hat/Fedora, Alpine Linux.

## Usage

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio": {
        "ref": "latest"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | `github` | Repository host platform (`github`, `gitlab`, `codeberg`, `bitbucket`). |
| `repository` | string | `gregorio-project/gregorio` | Repository in `OWNER/REPO` format (e.g. `gregorio-project/gregorio`). Combined with `host` to construct the full repository URL. |
| `ref` | string | `""` | Git reference (commit hash, tag, or branch name) to check out. Examples: `latest`, `v6.2.0`, `main`, or a commit hash. Leave empty to skip source installation and use the version bundled with TeX Live. |

## How it works

When `ref` is non-empty, the feature:

1. Installs build dependencies (CMake, GCC, Python 3, FontForge, pkg-config) from the native package manager.
2. Constructs the repository URL from `host` and `repository`.
3. Resolves `ref` (if set to `latest`, fetches the latest release tag).
4. Downloads the Gregorio source tarball for the requested reference.
5. Builds and installs via CMake (`/usr/local` prefix).
6. Runs `texhash` / `mktexlsr` to register the TeX files with the TeX filename database.
7. **Removes all build-only dependencies** that were not already present in the image.

The source-built binary and TeX files take priority over the version shipped with TeX Live.

## Prerequisites

This feature is intended to be used after the `texlive` feature from the same repository:

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/texlive": {},
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio": {
        "gregorio_version": "latest"
    }
}
```

## Notes

- Build dependencies are recorded before installation; only packages that were **not** already present in the image are removed afterwards, so pre-existing toolchains are left intact.
- Cargo's home and target directories are placed inside a temporary directory and cleaned up automatically on exit.
- Historical Gregorio releases may require a specific TeX Live version. Refer to the [Gregorio release notes](https://github.com/gregorio-project/gregorio/releases) for compatibility details.
