# Gregorio LSP

Installs [gregorio-lsp](https://github.com/aiscgre-br/gregorio-lsp) — the language server for Gregorio — along with the `grelint` and `grefmt` tools from source on Debian/Ubuntu, Red Hat/Fedora, or Alpine Linux.

Supported base images: Debian/Ubuntu, Red Hat/Fedora, Alpine Linux.

## Usage

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio-lsp": {
        "ref": "latest"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | `github` | Repository host platform (`github`, `gitlab`, `codeberg`, `bitbucket`). |
| `repository` | string | `aiscgre-br/gregorio-lsp` | Repository in `OWNER/REPO` format (e.g. `aiscgre-br/gregorio-lsp`). Combined with `host` to construct the full repository URL. |
| `ref` | string | `""` | Git reference (commit hash, tag, or branch name) to check out. Examples: `latest`, `v0.9.4`, `main`, or a commit hash. Leave empty to skip installation. |

## How it works

When `ref` is non-empty the feature:

1. Installs the Rust toolchain (`rustc` + `cargo`) from the native package manager.
2. Constructs the repository URL from `host` and `repository`.
3. Resolves `ref` (if set to `latest`, fetches the latest release tag).
4. Downloads the gregorio-lsp source tarball for the requested reference.
5. Builds all three binaries with `cargo build --release`.
6. Installs `gregorio-lsp`, `grelint`, and `grefmt` to `/usr/local/bin`.
7. **Removes the Rust toolchain** (and any other build-only packages) that were not already present in the image.

## Prerequisites

To use gregorio-lsp with Gregorio, you may want to install both features:

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/texlive": {},
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio": {
        "ref": "latest"
    },
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio-lsp": {
        "ref": "latest"
    }
}
```

## Notes

- Build dependencies are recorded before installation; only packages that were **not** already present in the image are removed afterwards, so pre-existing toolchains are left intact.
- Cargo's home and target directories are placed inside a temporary directory and cleaned up automatically on exit.
