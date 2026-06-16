# texlive

Installs [TeX Live](https://www.tug.org/texlive/) via the official TUG network installer on Debian/Ubuntu, Red Hat/Fedora, or Alpine Linux containers.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scheme` | string | `full` | TeX Live scheme to install. See [TeX Live schemes](https://www.tug.org/texlive/doc/texlive-en/texlive-en.html#x1-340003.3). |
| `packages` | string | `""` | Space-separated list of additional tlmgr packages to install after the base scheme. |
| `release` | string | `latest` | TeX Live release year (`latest`, `2026`, `2025`, ..., `2015`) or `latest` for the current release. |
| `mirror` | string | `""` | Custom tlnet mirror URL (must point to a directory containing `tlpkg/`). |

## Available Schemes

| Scheme | Description |
|--------|-------------|
| `full` | Complete TeX Live installation (~7 GB) |
| `medium` | Commonly used packages (~2 GB) |
| `small` | Plain TeX + LaTeX + basic extras (~1 GB) |
| `basic` | Plain TeX + LaTeX, no extras |
| `minimal` | Plain TeX only |
| `infraonly` | Infrastructure only (tlmgr), no packages |

## Notes

- Binaries are symlinked into `/usr/local/bin` so they are on `PATH` without modifying shell profiles.
- `MANPATH` and `INFOPATH` environment variables are set to include TeX Live man and info pages.
- For historical releases, the installer is fetched from `https://ftp.tug.org/texlive/historic/<year>/`.
- A custom mirror must expose a standard tlnet tree (i.e., contain `tlpkg/texlive.tlpdb`).
