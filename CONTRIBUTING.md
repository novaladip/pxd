# Contributing

`pxd` is proprietary software and its source code lives in a private
repository. This repository only hosts the install scripts, documentation and
release artifacts, so **pull requests with code changes cannot be accepted
here**.

What is welcome:

- **Bug reports.** Include `pxd version`, the operating system and architecture,
  the exact command, and (for `--json` commands) the JSON failure envelope.
  Redact tokens and paths you do not want to share.
- **Documentation fixes** in `README.md` or `USAGE.md` that do not require
  knowledge of the private source.
- **Install-script fixes.** `install.sh` and `install.ps1` are the canonical
  files; keep changes POSIX-`sh`/PowerShell 5.1 compatible, keep the checksum
  verification intact, and never add a path that installs unverified bytes.

For anything that needs source access, or for a security report, see
[SECURITY.md](SECURITY.md).
