# Security policy

`pxd` is proprietary software; its source code is not public.

## Reporting a vulnerability

Please **do not** open a public issue for a suspected vulnerability.

Report it privately to the maintainer (`novaladip`) through GitHub's private
vulnerability reporting on this repository (Security → Advisories → "Report a
vulnerability"), or by email if you already have a contact address.

Include:

- affected `pxd` version (`pxd version`) and platform,
- a description of the impact,
- reproduction steps or a proof of concept,
- whether the issue is in the binary, the install scripts, or the release
  pipeline.

You will get an acknowledgement within a few working days. Please give us a
reasonable window to ship a fix before disclosing publicly.

## Verifying downloads

Every release publishes `checksums.txt` (SHA-256) covering all archives, and
`install.sh` / `install.ps1` verify it before installing. If a checksum does not
match, do not run the binary: report it using the process above.
