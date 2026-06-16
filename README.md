# devcontainer-features-texlive

[Dev Container Features](https://containers.dev/implementors/features/) for installing [TeX Live](https://www.tug.org/texlive/) in Debian/Ubuntu, Red Hat/Fedora, and Alpine based dev containers.

## Features

| Feature | Description |
|---------|-------------|
| [`texlive`](src/texlive/README.md) | Installs TeX Live via the official TUG network installer |

## Usage

Add the feature to your `devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/aiscgre-br/devcontainer-features-texlive/texlive:1": {}
    }
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scheme` | string | `full` | TeX Live scheme (`full`, `medium`, `small`, `basic`, `minimal`, `infraonly`) |
| `packages` | string | `""` | Space-separated list of additional tlmgr packages to install |
| `release` | string | `latest` | TeX Live release year (`latest`, `2026`, `2025`, `2024`, ...) |
| `mirror` | string | `""` | Custom tlnet mirror URL |

### Examples

**Full install, latest release (default):**
```jsonc
{
    "features": {
        "ghcr.io/aiscgre-br/devcontainer-features-texlive/texlive:1": {}
    }
}
```

**Basic scheme with extra packages:**
```jsonc
{
    "features": {
        "ghcr.io/aiscgre-br/devcontainer-features-texlive/texlive:1": {
            "scheme": "basic",
            "packages": "latexmk biber csquotes"
        }
    }
}
```

**Specific release with custom mirror:**
```jsonc
{
    "features": {
        "ghcr.io/aiscgre-br/devcontainer-features-texlive/texlive:1": {
            "release": "2024",
            "mirror": "https://mirrors.rit.edu/CTAN/systems/texlive/tlnet"
        }
    }
}
```

## Included Perl Dependencies

The installer ensures all Perl modules required by `latexindent` are available:

- `YAML::Tiny`
- `File::HomeDir`
- `Unicode::GCString` (via `Unicode::LineBreak`)
- `Log::Dispatch`
- `Log::Log4perl`
- `File::Which`
- `Sub::Identify`

## License

MIT — see [LICENSE](LICENSE).
