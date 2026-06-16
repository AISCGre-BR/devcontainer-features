# CLAUDE.md — devcontainer-features

## Project overview

This repository provides a [Dev Container Feature](https://containers.dev/implementors/features/) that installs **TeX Live** using the official TUG network installer (`install-tl`). The feature supports Debian/Ubuntu, Red Hat/Fedora, and Alpine Linux base images.

## Repository layout

```
.
├── src/
│   └── texlive/
│       ├── devcontainer-feature.json   # Feature metadata and option declarations
│       ├── install.sh                  # Installation script (runs as root inside the container)
│       └── README.md                  # Feature-level documentation
├── test/
│   └── texlive/
│       ├── scenarios.json              # Test matrix (option combinations to exercise)
│       └── test.sh                    # Smoke tests using dev-container-features-test-lib
├── .github/
│   └── workflows/
│       ├── test.yml                    # CI: runs feature tests on push/PR
│       └── release.yml                 # CD: publishes to GHCR on tag push
├── CLAUDE.md                           # This file
├── LICENSE
└── README.md
```

## Feature options

Declared in `src/texlive/devcontainer-feature.json` and consumed as environment variables inside `install.sh` (uppercased, e.g. `SCHEME`, `PACKAGES`, `RELEASE`, `MIRROR`).

| Option | Env var | Default | Notes |
|--------|---------|---------|-------|
| `scheme` | `$SCHEME` | `full` | Passed to `install-tl` as `scheme-<value>` |
| `packages` | `$PACKAGES` | `""` | Space-separated; fed to `tlmgr install` |
| `release` | `$RELEASE` | `latest` | `latest` → CTAN mirror; year → TUG historic |
| `mirror` | `$MIRROR` | `""` | Overrides URL construction when non-empty |

## Install script logic (`src/texlive/install.sh`)

1. **OS detection** — reads `/etc/os-release`; identifies Debian-like, Red Hat-like, or Alpine.
2. **Prerequisites** — installs `wget`, `curl`, `fontconfig`, `perl`, and all Perl modules needed by `latexindent` using the native package manager.
3. **URL resolution** — builds the installer URL and tlnet repo URL from `$RELEASE` and `$MIRROR`.
4. **Download** — fetches `install-tl-unx.tar.gz` to a temp directory (cleaned up on exit).
5. **Profile generation** — writes a non-interactive profile (`texlive.profile`) under `$TEXLIVE_PREFIX/<release>/`.
6. **Installation** — runs `install-tl --profile --location --no-interaction`.
7. **PATH setup** — symlinks every binary from the arch-specific bin dir into `/usr/local/bin`; creates stable symlinks for man/info pages.
8. **Extra packages** — if `$PACKAGES` is non-empty, calls `tlmgr install`.
9. **Perl validation** — checks each required module with `perl -M<mod> -e 1`; installs missing ones via `cpanm`.

### `latexindent` Perl dependencies

`latexindent` ships with TeX Live but requires several Perl modules that are not bundled:

| Module | Debian package | RPM package | Alpine package |
|--------|---------------|-------------|----------------|
| `YAML::Tiny` | `libyaml-tiny-perl` | `perl-YAML-Tiny` | `perl-yaml-tiny` |
| `File::HomeDir` | `libfile-homedir-perl` | `perl-File-HomeDir` | `perl-file-homedir` |
| `Unicode::GCString` | `libunicode-linebreak-perl` | `perl-Unicode-LineBreak` | `perl-unicode-linebreak` |
| `Log::Dispatch` | `liblog-dispatch-perl` | `perl-Log-Dispatch` | `perl-log-dispatch` |
| `Log::Log4perl` | `liblog-log4perl-perl` | `perl-Log-Log4perl` | `perl-log-log4perl` |
| `File::Which` | `libfile-which-perl` | `perl-File-Which` | `perl-file-which` |
| `Sub::Identify` | `libsub-identify-perl` | `perl-Sub-Identify` | `perl-sub-identify` |

If any module is missing after the native package install, the script falls back to `cpanm`.

## Adding a new OS family

1. Add a new `is_<family>()` function in `install.sh`.
2. Extend `pkg_install`, `update_pkg_index`, and `install_prerequisites` with the new branch.
3. Add the native Perl package names for that distro to the table above.
4. Test with `devcontainer features test --features texlive --base-image <image>`.

## Running tests locally

Requires the [Dev Container CLI](https://github.com/devcontainers/cli) and Docker:

```bash
devcontainer features test \
    --features texlive \
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

1. Bump `version` in `src/texlive/devcontainer-feature.json`.
2. Commit and push to `main`.
3. Create and push a Git tag: `git tag v1.x.y && git push origin v1.x.y`.
4. The `release.yml` workflow publishes the feature to `ghcr.io/aiscgre-br/devcontainer-features/texlive`.

## Key constraints and gotchas

- The installer is downloaded fresh each time; caching is intentionally omitted to keep the feature stateless and simple.
- `install-tl` creates a versioned directory (e.g. `2026`) inside `$TEXLIVE_PREFIX`. When `$RELEASE=latest`, the script discovers the actual directory with `find` after installation.
- The `PATH` is not modified in shell profiles because devcontainer Features run as root and the container's `PATH` is set via the `containerEnv` field in `devcontainer-feature.json`. Symlinks in `/usr/local/bin` are the preferred mechanism.
- Historical releases are immutable on TUG servers; `tlmgr update` is not expected to work for them.
