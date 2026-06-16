# Tree-Sitter Gregorio

Installs [tree-sitter-gregorio](https://github.com/gregorio-project/tree-sitter-gregorio) — the Tree-sitter grammar for parsing Gregorio GABC notation — from source on Debian/Ubuntu, Red Hat/Fedora, or Alpine Linux.

Supported base images: Debian/Ubuntu, Red Hat/Fedora, Alpine Linux.

## Usage

```jsonc
"features": {
    "ghcr.io/aiscgre-br/devcontainer-features/tree-sitter-gregorio": {
        "ref": "latest"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | string | `github` | Repository host platform (`github`, `gitlab`, `codeberg`, `bitbucket`). |
| `repository` | string | `gregorio-project/tree-sitter-gregorio` | Repository in `OWNER/REPO` format (e.g. `gregorio-project/tree-sitter-gregorio`). Combined with `host` to construct the full repository URL. |
| `ref` | string | `""` | Git reference (commit hash, tag, or branch name) to check out. Examples: `latest`, `v1.0.0`, `main`, or a commit hash. Leave empty to skip installation. |

## How it works

When `ref` is non-empty, the feature:

1. Installs build dependencies (build tools, GCC, make, tree-sitter CLI, pkg-config) from the native package manager.
2. Constructs the repository URL from `host` and `repository`.
3. Resolves `ref` (if set to `latest`, fetches the latest release tag).
4. Downloads the tree-sitter-gregorio source tarball for the requested reference.
5. Builds the grammar using the project's build system (make, build.sh, or npm).
6. Installs the compiled grammar library to `/usr/local/lib/tree-sitter/grammars/`.
7. **Removes all build-only dependencies** that were not already present in the image.

## Integration with editors and tools

The compiled grammar is available at `/usr/local/lib/tree-sitter/grammars/gregorio.so` for use with:
- Neovim with tree-sitter
- Helix editor
- Emacs with tree-sitter support
- Other tree-sitter-enabled tools

## Notes

- Build dependencies are recorded before installation; only packages that were **not** already present in the image are removed afterwards, so pre-existing toolchains are left intact.
- The grammar installation path follows the standard tree-sitter conventions.
