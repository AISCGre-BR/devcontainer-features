# Gregorio

Installs [Gregorio](https://gregorio-project.github.io/) — the Gregorian chant score engraver — from source, and optionally the [gregorio-lsp](https://github.com/aiscgre-br/gregorio-lsp) language server (which also provides `grelint` and `grefmt`).

Supported base images: Debian/Ubuntu, Red Hat/Fedora, Alpine Linux.

## Usage

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/gregorio": {
        "gregorio_version": "latest",
        "gregorio_lsp_version": "latest"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gregorio_version` | string | `""` | Gregorio version to build and install from source (e.g. `latest`, `6.2.0`). Takes priority over the version bundled with TeX Live. Leave empty to use the TeX Live bundled version without any source build. |
| `gregorio_repository` | string | `https://github.com/gregorio-project/gregorio` | GitHub repository URL for the Gregorio project. |
| `gregorio_lsp_version` | string | `""` | Version of [gregorio-lsp](https://github.com/aiscgre-br/gregorio-lsp) to build and install (`latest` or any published tag such as `v0.9.4`). Installs the `gregorio-lsp` language server plus `grelint` and `grefmt`. Leave empty to skip. |

## How it works

### Gregorio (`gregorio_version`)

When a version is specified the feature:

1. Installs build dependencies (CMake, GCC, Python 3, FontForge, pkg-config) from the native package manager.
2. Downloads the Gregorio source tarball for the requested version from `gregorio_repository`.
3. Builds and installs via CMake (`/usr/local` prefix).
4. Runs `texhash` / `mktexlsr` to register the TeX files with the TeX filename database.
5. **Removes all build-only dependencies** that were not already present in the image.

The source-built binary and TeX files take priority over the version shipped with TeX Live.

### gregorio-lsp (`gregorio_lsp_version`)

When a version is specified the feature:

1. Installs the Rust toolchain (`rustc` + `cargo`) from the native package manager.
2. Downloads the gregorio-lsp source tarball.
3. Builds all three binaries with `cargo build --release`.
4. Installs `gregorio-lsp`, `grelint`, and `grefmt` to `/usr/local/bin`.
5. **Removes the Rust toolchain** (and any other build-only packages) that were not already present in the image.

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
