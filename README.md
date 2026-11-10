# pxd

`pxd` is the command-line client for [Personax Drive](https://personax-drive.cotc.dev).
It is built for scripts, agents and CI: no prompts, stable `--json` output, and
documented exit codes.

This repository is the **release-only** home of pxd: install scripts, release
notes and prebuilt binaries. The source code is private.

- Usage guide: [USAGE.md](USAGE.md)
- Releases: <https://github.com/novaladip/pxd/releases>
- Short URLs: <https://pxd.cotc.dev>

## Install

### macOS and Linux

```sh
curl -fsSL https://pxd.cotc.dev/install.sh | sh
```

Pin a version (recommended in CI and for agents, so a run is reproducible):

```sh
curl -fsSL https://pxd.cotc.dev/install.sh | PXD_VERSION=v1.2.3 sh
```

Pick a different directory than `~/.local/bin`:

```sh
curl -fsSL https://pxd.cotc.dev/install.sh | PXD_INSTALL_DIR="$HOME/bin" sh
```

The installer detects the OS and CPU architecture (including Rosetta on Apple
silicon), downloads the archive **and `checksums.txt`**, verifies the SHA-256 and
only then installs. It never uses `sudo` and never installs unverified bytes.

### Windows

```powershell
irm https://pxd.cotc.dev/install.ps1 | iex
```

The script detects the architecture, verifies the SHA-256, installs to
`%LOCALAPPDATA%\pxd\bin` and adds that directory to your user `PATH`.

Pin a version the same way as on Unix:

```powershell
$env:PXD_VERSION = "v1.2.3"; irm https://pxd.cotc.dev/install.ps1 | iex
```

### Manual download

Every release ships `pxd_<version>_<os>_<arch>.tar.gz` (`.zip` on Windows),
version-less aliases `pxd_<os>_<arch>.tar.gz` (so `releases/latest/download/...`
is stable) and a `checksums.txt` covering all of them.

| OS | Architecture | Version-less asset |
| --- | --- | --- |
| Linux | x86-64 | `pxd_linux_amd64.tar.gz` |
| Linux | arm64 | `pxd_linux_arm64.tar.gz` |
| macOS | Intel | `pxd_darwin_amd64.tar.gz` |
| macOS | Apple silicon | `pxd_darwin_arm64.tar.gz` |
| Windows | x86-64 | `pxd_windows_amd64.zip` |
| Windows | arm64 | `pxd_windows_arm64.zip` |

The versioned names follow the same pattern, e.g.
`pxd_1.2.3_linux_amd64.tar.gz`.

Always verify the checksum:

```sh
base=https://github.com/novaladip/pxd/releases/latest/download
os=linux; arch=amd64
curl -fsSLO "$base/pxd_${os}_${arch}.tar.gz"
curl -fsSLO "$base/checksums.txt"
grep " pxd_${os}_${arch}.tar.gz\$" checksums.txt | sha256sum -c -
tar -xzf "pxd_${os}_${arch}.tar.gz" pxd
install -m 0755 pxd ~/.local/bin/pxd
pxd version
```

On macOS use `shasum -a 256 -c -` instead of `sha256sum -c -`. On Windows,
compare `(Get-FileHash .\pxd_windows_amd64.zip).Hash` with the line in
`checksums.txt` before extracting.

## Update

```sh
pxd update           # latest release
pxd update --check   # only report whether a newer version exists
pxd update --version v1.2.4
```

`pxd update` downloads the archive, verifies the SHA-256 and atomically replaces
the running binary.

`pxd` also prints a one-line notice on stderr when a newer release exists (at
most once a day, never in scripts). Disable it with `PXD_NO_UPDATE_CHECK=1`.

## Support

- Bugs and feature requests: open an issue on this repository.
- Security reports: see [SECURITY.md](SECURITY.md).
- `pxd` is proprietary software; see [LICENSE](LICENSE).
