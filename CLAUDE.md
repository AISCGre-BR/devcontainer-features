# CLAUDE.md — devcontainer-features

## Project overview

This repository provides four [Dev Container Features](https://containers.dev/implementors/features/):

| Feature | Version | Description | Build system |
|---------|---------|-------------|--------------|
| `texlive` | 2.0.7 | Installs TeX Live via the official TUG network installer | Shell (`install-tl`) |
| `gregorio` | 2.0.8 | Builds and installs Gregorio (Gregorian chant engraver) from source | **Autotools** (`autoreconf` + `./configure` + `make`) |
| `gregorio-lsp` | 1.0.6 | Builds and installs the Gregorio language server (`gregorio-lsp`, `grelint`, `grefmt`) from source | **Cargo** (`cargo build --release`) |
| `tree-sitter-gregorio` | 1.0.4 | Builds and installs the tree-sitter-gregorio grammar from source | **Make** / npm (grammar-dependent) |

All features support Debian/Ubuntu, Red Hat/Fedora, and Alpine Linux base images.

## Repository layout

```
.
├── src/
│   ├── texlive/
│   │   ├── devcontainer-feature.json
│   │   ├── install.sh
│   │   └── README.md
│   ├── gregorio/
│   │   ├── devcontainer-feature.json
│   │   ├── install.sh
│   │   └── README.md
│   ├── gregorio-lsp/
│   │   ├── devcontainer-feature.json
│   │   ├── install.sh
│   │   └── README.md
│   └── tree-sitter-gregorio/
│       ├── devcontainer-feature.json
│       ├── install.sh
│       └── README.md
├── test/
│   ├── texlive/
│   │   ├── scenarios.json
│   │   └── test.sh
│   ├── gregorio/
│   │   ├── scenarios.json
│   │   └── test.sh
│   ├── gregorio-lsp/
│   │   └── scenarios.json
│   └── tree-sitter-gregorio/
│       └── scenarios.json
├── .github/
│   └── workflows/
│       ├── test.yml        # CI: runs feature tests on push/PR
│       └── release.yml     # CD: publishes all features to GHCR on tag push
├── CLAUDE.md
├── LICENSE
└── README.md
```

## `devcontainer-features-install.sh` (all features)

All four features ship a custom `devcontainer-features-install.sh` entrypoint instead of relying on the auto-generated one from `devcontainers/action@v1`.

**Why:** Some devcontainer implementations (confirmed: Zed/podman) generate `devcontainer-features.env` without quoting option values. Sourcing an unquoted file directly causes space-separated values (e.g. `PACKAGES=babel-latin babel-portuges ...`) to be split by the shell: the first word becomes a variable-assignment prefix and the rest is executed as a command, failing with exit 127.

**How it works:** The script reads `devcontainer-features.env` line-by-line with `IFS= read -r`, extracts `KEY` and full `VALUE` (preserving spaces) for each `KEY=value` line, and calls `export "${KEY}=${VALUE}"` — nothing is executed as a command. It then calls `./install.sh`.

The devcontainer spec explicitly supports this: *"A Feature MAY include a `devcontainer-features-install.sh` that serves as an entrypoint."* When present, `devcontainers/action@v1` packages it as-is instead of generating a default one.

## Shared install script structure

All four `install.sh` scripts share the same skeleton:

1. **sh bootstrap** — the shebang is `#!/bin/sh`; if bash is not available (Alpine), it installs it and re-execs itself under bash, because bash arrays are used for `_BUILD_PKGS_TO_REMOVE`.
2. **OS detection** — reads `/etc/os-release`; identifies Debian-like, Red Hat-like, or Alpine via `is_debian_like()`, `is_redhat_like()`, `is_alpine()`.
3. **Package manager helpers** — `pkg_install`, `pkg_remove`, `update_pkg_index`, `is_pkg_installed`, `install_build_deps`, `remove_build_deps`.
4. **URL construction** — `construct_repo_url` and `construct_tarball_url` build forge URLs from `$HOST` and `$REPOSITORY`. Supported hosts: `github`, `gitlab`, `codeberg`, `bitbucket`.
5. **`ref` resolution** — empty `$REF` → `HEAD`; `"latest"` → resolved via forge API; anything else → passed as-is to the archive endpoint (branch name, tag name, or commit hash — no normalization).
6. **Download** — fetches a source tarball into `$BUILD_DIR` (cleaned on EXIT trap).
7. **Build and install** — feature-specific (see sections below).
8. **Cleanup** — `remove_build_deps` removes packages that were not present before the build.

## `texlive` feature

**Options** (`src/texlive/devcontainer-feature.json`):

| Option | Env var | Default | Notes |
|--------|---------|---------|-------|
| `scheme` | `$SCHEME` | `full` | Passed to `install-tl` as `scheme-<value>` |
| `packages` | `$PACKAGES` | `""` | Space-separated; fed to `tlmgr install` |
| `release` | `$RELEASE` | `latest` | `latest` → CTAN mirror; year → TUG historic |
| `mirror` | `$MIRROR` | `""` | Overrides URL construction when non-empty |

**Install logic** (`src/texlive/install.sh`):

1. Installs `wget`, `curl`, `fontconfig`, `perl`, and all Perl modules needed by `latexindent`.
2. Builds the installer URL and tlnet repo URL from `$RELEASE` and `$MIRROR`.
3. Fetches `install-tl-unx.tar.gz` to a temp directory.
4. Writes a non-interactive profile (`texlive.profile`) and runs `install-tl`.
5. Symlinks every binary from the arch-specific bin dir into `/usr/local/bin`.
6. If `$PACKAGES` is non-empty, calls `tlmgr install`.
7. Validates Perl modules with `perl -M<mod> -e 1`; installs missing ones via `cpanm`.

**Key constraints:**
- `install-tl` creates a versioned directory (e.g. `2026`) inside `$TEXLIVE_PREFIX`. When `$RELEASE=latest`, the script discovers the actual directory with `find` after installation.
- The `PATH` is set via `containerEnv` in `devcontainer-feature.json`; symlinks in `/usr/local/bin` are the preferred mechanism.
- Historical releases are immutable on TUG servers; `tlmgr update` is not expected to work for them.

### `latexindent` Perl dependencies

| Module | Debian package | RPM package | Alpine package |
|--------|---------------|-------------|----------------|
| `YAML::Tiny` | `libyaml-tiny-perl` | `perl-YAML-Tiny` | `perl-yaml-tiny` |
| `File::HomeDir` | `libfile-homedir-perl` | `perl-File-HomeDir` | `perl-file-homedir` |
| `Unicode::GCString` | `libunicode-linebreak-perl` | `perl-Unicode-LineBreak` | `perl-unicode-linebreak` |
| `Log::Dispatch` | `liblog-dispatch-perl` | `perl-Log-Dispatch` | `perl-log-dispatch` |
| `Log::Log4perl` | `liblog-log4perl-perl` | `perl-Log-Log4perl` | `perl-log-log4perl` |
| `File::Which` | `libfile-which-perl` | `perl-File-Which` | `perl-file-which` |
| `Sub::Identify` | `libsub-identify-perl` | `perl-Sub-Identify` | `perl-sub-identify` |

## `gregorio` feature

**Build system: Autotools** (`configure.ac` + `Makefile.am`). The repository does **not** use CMake.

**Build dependencies:**

| | Debian | RPM | Alpine |
|-|--------|-----|--------|
| autoconf | `autoconf` | `autoconf` | `autoconf` |
| automake | `automake` | `automake` | `automake` |
| libtool | `libtool` | `libtool` | `libtool` |
| C compiler | `gcc` | `gcc` | `gcc` |
| make | `make` | `make` | `make` |
| lexer generator | `flex` | `flex` | `flex` |
| parser generator | `bison` | `bison` | `bison` |
| Python 3 | `python3` | `python3` | `python3` |
| FontForge | `fontforge` | `fontforge` | `fontforge` |
| pkg-config | `pkg-config` | `pkgconf` | `pkgconfig` |

`flex` and `bison` are required to generate the lexer/parser C sources (`gabc-notes-determination`, `gabc-score-determination`, `vowel-rules`) from the `.l`/`.y` files in the repository.

**Build sequence** (inside a subshell in `src_dir`):

```sh
autoreconf -fi                   # generate ./configure from configure.ac
bash ./configure --prefix=/usr/local  # bash required: configure uses CFLAGS+= (bash-ism, breaks busybox ash)
make -j$(nproc)
make install
```

After installation, `texhash` (or `mktexlsr`) is called to refresh the TeX filename database so `TEXMFLOCAL` files are found.

**`installsAfter`:** this feature declares `ghcr.io/aiscgre-br/devcontainer-features/texlive` so Gregorio is installed after TeX Live.

## `gregorio-lsp` feature

**Build system: Cargo** (Rust). Produces three binaries: `gregorio-lsp`, `grelint`, `grefmt`.

**Build dependencies:** `rust`, `cargo`, `gcc`, `pkg-config` (plus `musl-dev` on Alpine).

**Build sequence:**

```sh
export CARGO_HOME="${BUILD_DIR}/cargo-home"
export CARGO_TARGET_DIR="${BUILD_DIR}/cargo-target"
cargo build --release --locked   # falls back to cargo build --release if Cargo.lock is absent
```

Binaries are copied from `$CARGO_TARGET_DIR/release/` to `/usr/local/bin/`. Cargo's home and target directories are redirected into `$BUILD_DIR` so nothing leaks into the container's home directory.

## `tree-sitter-gregorio` feature

**Build system:** determined at runtime — the script tries, in order: `Makefile` → `build.sh` → `package.json` (npm). Compiled grammar (`.so`) is installed to `/usr/local/lib/tree-sitter/grammars/gregorio.so`.

## `ref` option (all source-built features)

All three source-built features (`gregorio`, `gregorio-lsp`, `tree-sitter-gregorio`) share the same `ref` option and resolution logic:

| Value | Behaviour |
|-------|-----------|
| `""` (empty) | Downloads `HEAD` of the repository's default branch |
| `"latest"` | Resolves the latest release tag via the forge API, then downloads that ref |
| Any other string | Passed as-is to the forge archive endpoint — can be a branch name, a tag name (exact, including any `v` prefix), or a commit hash |

> **Note:** the script does not normalize or guess ref types. If the upstream tag is `v6.2.0`, the user must pass `v6.2.0`, not `6.2.0`.

## Adding a new OS family

1. Add a new `is_<family>()` detection function in each `install.sh`.
2. Extend `pkg_install`, `pkg_remove`, `update_pkg_index`, and `is_pkg_installed` with the new branch.
3. Add build-dependency package names for that distro to the relevant tables above.
4. Test with `devcontainer features test --features <feature> --base-image <image> .`.

## Running tests locally

Requires the [Dev Container CLI](https://github.com/devcontainers/cli) and Docker:

```bash
devcontainer features test \
    --features gregorio \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
    .
```

To test a specific scenario:

```bash
devcontainer features test \
    --features texlive \
    --base-image mcr.microsoft.com/devcontainers/base:debian \
    --scenario install_basic_latest \
    .
```

## Publishing a new release

1. Bump `version` in the relevant `src/<feature>/devcontainer-feature.json` file(s).
2. Commit and push to `main`.
3. Create and push a Git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. The `release.yml` workflow triggers on `v*` tags and publishes **all** features to GHCR using the `version` field in each `devcontainer-feature.json`.

The repo-level tag tracks the highest feature version across a release batch. Only features whose `version` field changed will be re-published by the `devcontainers/action`.
