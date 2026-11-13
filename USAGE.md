# pxd usage

> **Status: M5 (agent path + interactive TUI).** `pxd version`, `pxd config show`,
> `pxd config path`, `pxd login`, `pxd logout`, `pxd whoami`, `pxd doctor`,
> `pxd ls`, `pxd search`, `pxd tree`, `pxd stat`, `pxd mkdir`, `pxd upload`, `pxd download`,
> `pxd mv`, `pxd rename`, `pxd rm`, `pxd trash ls|restore|empty`, `pxd url`,
> `pxd link create`, `pxd token create|ls|revoke`, `pxd ui` and `pxd update` are
> available.
> **This file must be updated as each new command lands.**

`pxd` is the command-line client for Personax Drive. It is built for scripts,
agents and CI: no prompts, stable JSON, documented exit codes.

> **Agents and automation must use subcommands.** Bare `pxd` on a TTY opens an
> interactive full-screen UI (`pxd ui`); never invoke it from a script, agent or
> CI job. Always spell the subcommand (`pxd ls`, `pxd upload`, …), and use
> `--json` for a stable machine-readable contract. Off a terminal, bare `pxd`
> still prints help and `pxd ui` exits `2`.

## Install pxd (agents & CI)

Pin the version so a pipeline is reproducible, and install into a directory on
`PATH` without `sudo`:

```sh
curl -fsSL https://pxd.cotc.dev/install.sh | PXD_VERSION=v0.2.0 sh

# or from GitHub directly (same script; the domain is only a redirect):
curl -fsSL https://raw.githubusercontent.com/novaladip/pxd/main/install.sh \
  | PXD_VERSION=v0.2.0 PXD_INSTALL_DIR="$HOME/.local/bin" sh
```

The installer verifies the archive's SHA-256 against `checksums.txt` and aborts
on a mismatch; it is quote-safe for a Docker `RUN` step. `PXD_QUIET=1` silences
progress. Windows agents use `PXD_VERSION=v0.2.0` with
`irm https://pxd.cotc.dev/install.ps1 | iex`.

Keep an installed CLI current with `pxd update` (`--check` reports without
downloading). Interactive runs show a one-line "new version
available" notice on stderr at most once a day; set `PXD_NO_UPDATE_CHECK=1` in
agents and CI to turn it off entirely.


## Recipe: upload a build artifact and share it (CI)

Create a personal access token once, from a machine where you are signed in
interactively, and store it as the CI secret `PXD_TOKEN`:

```sh
pxd login
pxd token create --name ci-android --expires 90d   # copy the pxpat_... value now
# then, in the CI secret store:
#   PXD_TOKEN=pxpat_...
```

A PAT is long-lived and does not rotate, so it is safe for ephemeral and
parallel runners. `PXD_USERNAME`/`PXD_PASSWORD` still work but log in on every
run and are not recommended for agents.

```sh
export PXD_TOKEN="$PXD_CI_TOKEN"

pxd upload build/app-release.apk "/example/$PROJECT/" \
  --parents --name "app-$VERSION.apk" --on-conflict=overwrite --json
pxd link create "/example/$PROJECT/app-$VERSION.apk" --expires 7d --json
```

```json
{"ok":true,"node_id":"…","path":"/example/myapp/app-1.4.0.apk","name":"app-1.4.0.apk","size":48213344,"mime_type":"application/vnd.android.package-archive","skipped":false,"replaced":"…"}
{"ok":true,"id":"…","url":"https://personax-drive.cotc.dev/s/…","expires_at":"2026-11-16T10:00:00Z","has_password":false}
```

`--parents` creates `/example/$PROJECT` when it does not exist yet,
`--on-conflict=overwrite` replaces a previous build of the same version, and
`--if-changed` makes a retried pipeline a no-op when the size is unchanged.

## Output contract

- **stdout** carries results only.
- **stderr** carries progress, diagnostics and human-readable errors.
- `--json` emits exactly one JSON object per command result/failure on stdout.
- `--plain`, non-TTY stdout, or `NO_COLOR` disables colour and styling. Plain
  output never contains ANSI escape sequences.
- `--quiet` suppresses progress/log lines (not results). `--verbose` adds
  diagnostics on stderr.
- The command tree never waits for interactive input. The only exceptions are
  `pxd login` in a fully interactive terminal and `--password-stdin`, which reads
  one line from stdin without prompting.
- Tokens and passwords are never written to stdout, stderr, logs or error
  messages, including with `--verbose`.

### Success envelope

Success responses always have `"ok": true`:

```json
{"ok":true,"version":"1.2.3","commit":"abc123","date":"2026-11-09T00:00:00Z"}
```

### Failure envelope

Failures with `--json` are written to stdout as:

```json
{"ok":false,"error_code":"NOT_FOUND","message":"node not found","details":{}}
```

`error_code` is the server's code when the failure came from an API call.
CLI-generated codes include `USAGE`, `UNEXPECTED`, `UNKNOWN_PROFILE`,
`NOT_LOGGED_IN`, `PAT_INVALID`, `INTERACTIVE_SESSION_REQUIRED`, `NETWORK`,
`INVALID_PATH`, `PATH_NOT_FOUND`, `NOT_A_FOLDER`, `IS_A_DIRECTORY`,
`AMBIGUOUS_PATH`, `AMBIGUOUS_NAME`, `INVALID_LOCAL_PATH`, `LOCAL_FILE_EXISTS`,
`DOWNLOAD_SIZE_MISMATCH`, `EMPTY_FILE`, `NOT_A_FILE`, `CONFIRMATION_REQUIRED`,
`CANCELLED`, `NODE_MOVE_INTO_SELF`, `NODE_MOVE_INTO_DESCENDANT`, `UNHEALTHY`,
`MANAGED_INSTALL`, `DEV_BUILD`, `CHECKSUM_MISMATCH`, `CHECKSUM_MISSING` and
`UPDATE_FAILED`. `details` is always an object (empty when there is no extra
context). Without `--json`, the message is written to stderr as
`error: <message>`.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success (including `"skipped": true` under `--on-conflict=skip` / `--if-changed`) |
| 1 | Unexpected error (also the server's code for an unmapped 4xx) |
| 2 | Usage error: unknown command/flag, bad arguments, `INVALID_PATH`, `NOT_A_FOLDER`, `IS_A_DIRECTORY`, `INVALID_LOCAL_PATH`, `EMPTY_FILE`, `CONFIRMATION_REQUIRED` |
| 3 | Authentication: missing, invalid, expired, or revoked credentials |
| 4 | Not found: `PATH_NOT_FOUND`, `NODE_NOT_FOUND`, any HTTP 404 |
| 5 | Conflict: `NODE_NAME_EXISTS`, `UPLOAD_NAME_EXISTS`, `LOCAL_FILE_EXISTS`, any HTTP 409 |
| 6 | Too large: `UPLOAD_TOO_LARGE`, HTTP 413 |
| 7 | Network / server unavailable — safe to retry (429, 5xx, dial/timeout/TLS) |

`NODE_MOVE_INTO_SELF` and `NODE_MOVE_INTO_DESCENDANT` exit `2` even though the
server reports them as 409. Unknown commands and unknown flags always exit `2`,
including with `--json`.
HTTP status mapping: 401 and 403 `USER_BANNED` → `3`, 404 → `4`, 409 → `5`,
413 or `UPLOAD_TOO_LARGE` → `6`, 429/5xx and transport errors (dial, timeout,
DNS, TLS) → `7`, other 4xx → `1` with the server's code.

## Paths

- Absolute paths (`/a/b/c`) only. Trailing slashes are ignored and a path is
  canonicalised before use.
- `.` and `..`, interior empty segments (`/a//b`) and segments longer than 255
  bytes are rejected with `INVALID_PATH` (exit 2).
- `id:<uuid>` addresses a node directly and skips path resolution. It is
  accepted everywhere a path is, and `path` in the output is derived from the
  node's breadcrumbs.
- Resolution walks one segment per request: the listing filter is a
  case-insensitive *substring* match, so only an exact, case-sensitive name
  match counts. `/readme.md` does not find `README.md`.
- A missing segment is `PATH_NOT_FOUND` (exit 4) with
  `details.missing_segment`; a file in the middle of a path is `NOT_A_FOLDER`
  (exit 2).
- Lookups are cached for the duration of one command only.

## Commands

```sh
pxd version [--json]
pxd config show [--json]
pxd config path [--json]
pxd login [--username <id>] [--password-stdin] [--json]
pxd logout [--all] [--json]
pxd whoami [--json]
pxd doctor [--json]
pxd ls [path] [-l] [--type file|folder] [--sort name|modified|size|type]
        [--order asc|desc] [-q <text>] [--all]
pxd search <query> [--limit N]
pxd tree [path] [--depth N] [--json]
pxd stat <path>
pxd mkdir [-p] <path>
pxd upload [-p|--parents] [-r|--recursive] [-j N] [--name <name>]
           [--on-conflict fail|skip|rename|overwrite] [--if-changed]
           <local...> <remote-dir>
pxd download [-r] [-j N] [--on-conflict fail|skip|overwrite|rename]
             <remote...> <local>
pxd mv <src...> <dst>
pxd rename <path> <new-name>
pxd rm [-r] [--permanent] [--yes] <path...>
pxd trash ls [--json]
pxd trash restore <id|name...>
pxd trash empty [--yes]
pxd url <path> [--inline]
pxd link create <path> [--expires 7d|24h|<RFC3339>] [--password-stdin]
pxd token create --name <name> [--expires 90d|never]
pxd token ls
pxd token revoke <id|name>
pxd ui
pxd update [--version vX.Y.Z] [--check] [--json]
pxd --help
```

`pxd ui` is interactive only: it requires stdin and stdout to be terminals and
exits `2` otherwise. It never produces a TUI result on stdout, and it refuses
`--json`; it is not part of the scriptable contract. Bare `pxd` opens the same UI
only when both ends are TTYs and neither `--json` nor `--plain` is set;
otherwise it prints help.

- `pxd` with no arguments prints help (and opens the TUI when stdin and stdout
  are both terminals and neither `--json` nor `--plain` is set).
- `pxd version` reports version/commit/build date injected with `-ldflags`.
- `pxd config show` prints the resolved profile, drive URL and auth URL plus
  the source of each value (`flag`, `env`, `file`, `default`).
- `pxd config path` prints the config file path. The file need not exist.
- `pxd login` authenticates and stores the session.
- `pxd logout` revokes the session and deletes local credentials.
- `pxd whoami` shows the user, credential source and token expiry, and verifies
  that Personax Drive accepts the token.

### doctor

```sh
pxd doctor --json
```

```json
{"ok":true,"healthy":true,"checks":[{"name":"config","ok":true,"detail":"profile=default drive_url=https://… (default) auth_url=https://… (default) file=/home/ci/.config/personax/cli.toml (missing)"},{"name":"drive_health","ok":true,"detail":"https://…/health is reachable"},{"name":"auth_health","ok":true,"detail":"https://…/health is reachable"},{"name":"credentials","ok":true,"detail":"source=env user=alice"},{"name":"credentials_valid","ok":true,"detail":"auth /auth/me and drive /api/v1/me accepted the token"},{"name":"credential_store","ok":true,"detail":"file"}]}
```

`pxd doctor` always prints one complete report and never prompts. `"ok"`
mirrors `"healthy"`. The exit code is the most severe failing check: `3` for
credentials, `7` for an unreachable server, `1` otherwise, `0` when all pass.
Because the report *is* the result, the usual error line/envelope is suppressed
so `--json` still emits exactly one object.

### update

```sh
pxd update --check --json
pxd update --json
pxd update --version v1.2.3 --json
```

```json
{"ok":true,"current":"v1.2.0","latest":"v1.3.0","update_available":true}
{"ok":true,"current":"v1.2.0","latest":"v1.3.0","updated":true,"path":"/home/alice/.local/bin/pxd"}
```

- The latest version is resolved **without the GitHub API**: `pxd` requests
  `https://github.com/novaladip/pxd/releases/latest` with redirects disabled and
  reads the `…/tag/vX.Y.Z` from `Location`. No token, no rate limit.
  `PXD_UPDATE_BASE` overrides the base URL (mirrors, tests).
- `--check` never downloads: it only compares versions and exits `0` (even when
  an update is available).
- Otherwise the archive for this OS/architecture and `checksums.txt` are
  fetched, the SHA-256 is verified, and the running binary is replaced
  atomically (a temporary file next to it is renamed over it). A checksum
  mismatch aborts with `CHECKSUM_MISMATCH` (exit `1`) and leaves the old binary
  untouched.
- Packaged yourself with Homebrew (`/Cellar/`) or Scoop (`…/scoop/apps/…`)?
  `pxd` refuses with `MANAGED_INSTALL` (exit `2`) and names the command to run
  (`brew upgrade pxd`, `scoop update pxd`).
- Development builds (`dev`, `…-dirty`, or not `vMAJOR.MINOR.PATCH`) refuse to
  self-update with `DEV_BUILD` (exit `2`) unless `--version` is given; `--check`
  still reports `update_available` when the latest release parses.
- Network failures are exit `7`; a missing release asset is exit `4`.

`pxd` also prints, on **stderr only**, at most once per 24 h:

```
A new pxd version is available: v1.2.0 → v1.3.0. Run `pxd update` (or your package manager).
```

The check runs in the background with a 1 s budget and never delays or fails a
command; it is skipped entirely for `pxd update`, development builds, `--json`,
`--quiet`, `--plain`, non-TTY output and when `PXD_NO_UPDATE_CHECK=1` is set.
The result is cached in `$XDG_CACHE_HOME/personax/update-check.json`
(`~/.cache/personax/` fallback).

### ls

```sh
pxd ls /example/myapp --json
```

```json
{"ok":true,"path":"/example/myapp","items":[{"id":"…","name":"app-1.4.0.apk","type":"file","size":48213344,"updated_at":"2026-11-09T10:00:00Z","path":"/example/myapp/app-1.4.0.apk"},{"id":"…","name":"builds","type":"folder","size":1024,"updated_at":"2026-11-09T09:00:00Z","path":"/example/myapp/builds"}],"total":2}
```

- Every page is fetched (100 per request), so the listing is complete.
- A file path prints that single node as the only item.
- `size` is the file size or a folder's recursive size; it can be `null` when
  the API does not load sizes.
- `mime_type` is never emitted: the node API does not expose a content type.
  The MIME type is only known to `pxd upload`, where it is chosen locally.
- Human output: folders get a trailing `/`. `-l` adds size, modified time and
  type. Plain (non-TTY) output is names only, or four tab-separated columns
  (`name`, `size`, `modified`, `type`) with `-l`, and no header.
- `--sort`/`--order`/`--type`/`-q` are passed to the server, which sorts and
  pages consistently. `q` is a case-insensitive substring match.
- `--all` includes entries whose name starts with `.` (hidden by default).
  Temp files created by `--on-conflict=overwrite` start with `.pxd-tmp-`.

### search

```sh
pxd search app --json
pxd search sunset --limit 10
```

```json
{"ok":true,"query":"app","items":[{"id":"…","name":"app-1.4.0.apk","type":"file","size":48213344,"updated_at":"2026-11-09T10:00:00Z","path":"/example/myapp/app-1.4.0.apk"}],"total":1}
```

- Searches the caller's whole drive by name. Matching is a case-insensitive
  substring match; `%` and `_` are literal characters. Leading and trailing
  whitespace is trimmed, and the query must then be 1–200 characters.
- The server ranks exact name matches first, then names that start with the
  query, then any other match; within a rank folders come before files, then the
  most recently updated. Trashed nodes, including a trashed folder's whole
  subtree, are excluded.
- `--limit` is `1..50` (default `20`). Search is a capped quick look, not a
  paginated listing: `total` is the number of hits returned.
- `path` is the full path including the hit itself; it is derived from the
  server's ancestor breadcrumbs. Plain (non-TTY) and human output print one full
  path per line, with a trailing `/` on folders.

### tree

```sh
pxd tree /docs --json
pxd tree /docs --depth 1
```

```json
{"ok":true,"path":"/docs","tree":{"id":"…","name":"docs","type":"folder","size":5,"path":"/docs","children":[{"id":"…","name":"a.txt","type":"file","size":2,"path":"/docs/a.txt"}]}}
```

- Recursive; every page of every folder is fetched. Children are sorted by name.
- `--depth N` limits how many levels below the path are shown. `0` prints only
  the path, `1` its direct children; the default is unlimited.
- Human terminals get box-drawing characters (`├──`, `└──`); plain/non-TTY
  output is indented by two spaces per level with no escape sequences.
- A file path prints the file as a single node with no `children`.

### stat

```sh
pxd stat /example/myapp/app-1.4.0.apk --json
```

```json
{"ok":true,"id":"…","parent_id":"…","name":"app-1.4.0.apk","type":"file","size":48213344,"created_at":"2026-11-09T09:59:00Z","updated_at":"2026-11-09T10:00:00Z","path":"/example/myapp/app-1.4.0.apk"}
```

`last_accessed_at` is present once the node has been read. The drive root
cannot be stat-ed (`INVALID_PATH`).

### mkdir

```sh
pxd mkdir /example/myapp --json
pxd mkdir -p /example/myapp/releases --json
```

```json
{"ok":true,"node_id":"…","path":"/example/myapp","created":true}
```

Without `-p` the parent must exist (`PATH_NOT_FOUND`, exit 4) and an existing
name is a conflict (`NODE_NAME_EXISTS`, exit 5). With `-p` every missing folder
is created and an existing path succeeds with `"created": false`. Losing a race
with another client that created the same folder is not an error: `pxd` re-reads
the folder and continues.

### upload

```sh
pxd upload [-p] [-r] [--name NAME] [--on-conflict MODE] [--if-changed] \
  <local...> <remote-dir>
```

The last argument is the destination folder; with `-p` it is created when
missing, otherwise it must already exist. `--name` requires exactly one local
file (not a directory). Local arguments are validated before any bytes are sent:
a missing, unreadable, empty or non-regular file fails up front.

Single file (`--json`):

```json
{"ok":true,"node_id":"…","path":"/example/myapp/app-1.4.0.apk","name":"app-1.4.0.apk","size":48213344,"mime_type":"application/vnd.android.package-archive","skipped":false,"replaced":"…"}
```

Several files (`--json`), one object per file:

```json
{"ok":true,"files":[{"node_id":"…","path":"/a/one.txt","name":"one.txt","size":3,"mime_type":"text/plain; charset=utf-8","skipped":false}],"uploaded":1,"skipped":0}
```

- `reason` appears when `skipped` is true: `"exists"` (`--on-conflict=skip`) or
  `"unchanged"` (`--if-changed`).
- `replaced` is the id of the node that `--on-conflict=overwrite` moved to the
  trash.
- `--name` is applied to the single uploaded file; otherwise the remote name is
  the local base name.
- `-r` recreates the directory tree, including empty directories. Without `-r`
  a directory argument is a usage error.
- `-j N` uploads up to N files at once (default 4, maximum 16). Directories are
  created before any file is sent. Results keep command order regardless of
  completion order. The command stops at the first failure, cancels the rest,
  and the failure's `details.completed` lists the files that were handled:
  ```json
  {"ok":false,"error_code":"UPLOAD_NAME_EXISTS","message":"File name already exists","details":{"status":409,"completed":[{"node_id":"…","path":"/a/one.txt","name":"one.txt","size":3,"mime_type":"text/plain; charset=utf-8","skipped":false}]}}
  ```

#### --on-conflict

| Mode | Behaviour |
| --- | --- |
| `fail` (default) | Exit `5` with the server's code (`UPLOAD_NAME_EXISTS` / `NODE_NAME_EXISTS`). Nothing is written. |
| `skip` | Do not upload. Result has `"skipped":true,"reason":"exists"`, exit `0`. |
| `rename` | Upload as `name (1).ext`, `name (2).ext`, … — the first free name. |
| `overwrite` | Upload under `.pxd-tmp-<8 hex>-<name>` in the same folder, trash the existing node, then rename the temporary node to the final name. The old version stays in the **trash** and remains restorable. |

Overwrite is safe by construction: the old file is never deleted before the new
node is fully completed. If the final rename fails, `pxd` restores the old node
and trashes the temporary one, then returns the error — the folder keeps exactly
the state it had. Overwriting a *folder* with a file is refused (`NODE_NAME_EXISTS`,
exit 5).

#### --if-changed

Skips the upload when a node with the target name already exists **and its size
equals the local file's size** (`"skipped":true,"reason":"unchanged"`, exit 0).
Otherwise `--on-conflict` decides what happens.

**Caveat:** the API exposes no checksum, so `--if-changed` compares the size
only. A rebuilt artifact with an identical size is *not* detected as changed;
combine it with `--on-conflict=overwrite` when a same-size change must still be
published, and version your artifact names (`app-$VERSION.apk`) for exact
idempotency.

#### Upload mechanics (for troubleshooting)

1. `POST /api/v1/uploads` creates a session; `UPLOAD_TOO_LARGE` (exit 6) is
   reported here, before any bytes are sent.
2. The file is streamed as `multipart/form-data` straight to the presigned
   storage URL with a precomputed `Content-Length` (never buffered in memory).
   No bearer token is sent to storage. All `upload_fields` go first and the file
   part last, with the declared content type.
3. `POST /api/v1/uploads/:id/complete` creates the node. `503
   UPLOAD_COMMIT_INDETERMINATE` means the outcome is unknown and is retried.

Create-session and complete are retried up to 4 attempts with exponential
backoff and jitter on network errors, 429 (honouring `Retry-After`) and
502/503/504. A failed storage POST is retried with a **new** upload session,
because a presigned POST may be single-use. Progress goes to stderr: a bar on a
TTY, a plain line at most every 2 s otherwise, nothing with `--json`/`--quiet`.

MIME types are chosen locally: an override table (`.apk` →
`application/vnd.android.package-archive`, `.aab` → `application/octet-stream`),
then `mime.TypeByExtension`, then content sniffing of the first 512 bytes, then
`application/octet-stream`. Zero-byte files cannot be uploaded (`EMPTY_FILE`,
exit 2).

### download

```sh
pxd download [-r] [-j N] [--on-conflict fail|skip|overwrite|rename] \
  <remote...> <local>
```

The last argument is the local destination:

- an existing directory: every remote lands inside it under its own name;
- a path that does not exist, with exactly one remote **file**: that path is the
  local file;
- with more than one remote, or any folder, a directory is used (created when
  missing) and each remote is placed inside under its name. A folder requires
  `-r`.

Bytes are fetched from the presigned storage URL with a **plain** client (no
bearer token) into `<local>.part`, fsynced and then renamed into place. A `.part`
left by an interrupted run is resumed with `Range` when storage answers `206`; a
`200` answer restarts from zero. A storage `403` means the presigned URL expired
and `pxd` fetches a fresh one exactly once. The final size is verified against
the node; a mismatch fails with `DOWNLOAD_SIZE_MISMATCH` (exit 1) and removes
the usable part.

Single file (`--json`):

```json
{"ok":true,"node_id":"…","path":"/example/app.apk","local_path":"/tmp/app.apk","size":48213344,"skipped":false}
```

Several files (`--json`):

```json
{"ok":true,"files":[{"node_id":"…","path":"/a/one.txt","local_path":"/tmp/one.txt","size":3,"skipped":false}],"downloaded":1,"skipped":0}
```

- `--on-conflict` applies to an existing **local** file:
  `fail` (default) exits `5` with `LOCAL_FILE_EXISTS`; `skip` reports
  `"skipped":true,"reason":"exists"`; `overwrite` replaces it only after the new
  file is complete; `rename` writes `name (1).ext`, `name (2).ext`, ….
- `-r` recreates the remote tree, including empty directories. Directories are
  created before any file is fetched. A folder without `-r` is `IS_A_DIRECTORY`
  (exit 2).
- `-j N` downloads up to N files at once (default 4, maximum 16). Results keep
  command/listing order. The first failure cancels the rest; the failure's
  `details.completed` lists the files already handled.
- Progress: an aggregate bar on a TTY, per-file lines in plain mode, nothing
  with `--json`/`--quiet`.

### mv

```sh
pxd mv /example/old.apk /archive
pxd mv /example/app.apk /archive/app-1.4.0.apk
```

- All sources are resolved before anything moves. The destination must be a
  folder; a file destination is `NOT_A_FOLDER` (exit 2).
- With one source and a destination that does not exist but whose parent folder
  does, `mv` moves **and renames**, like unix `mv`. If the rename fails the move
  is rolled back and the tree keeps its previous state.
- Moving a node into itself or into one of its descendants is exit `2`
  (`NODE_MOVE_INTO_SELF` / `NODE_MOVE_INTO_DESCENDANT`).
- Single (`--json`):

  ```json
  {"ok":true,"node_id":"…","from":"/example/app.apk","path":"/archive/app.apk"}
  ```

- Several sources (`--json`):

  ```json
  {"ok":true,"moves":[{"node_id":"…","from":"/a/x","path":"/b/x"}],"moved":1}
  ```

### rename

```sh
pxd rename /example/app.apk app-1.5.0.apk --json
```

```json
{"ok":true,"node_id":"…","from":"/example/app.apk","path":"/example/app-1.5.0.apk","name":"app-1.5.0.apk"}
```

The new name must be one path segment: no `/`, not `.` or `..`, at most 255
characters. The node stays in the same folder; an existing name there is exit
`5` (`NODE_NAME_EXISTS`).

### rm

```sh
pxd rm /example/old.txt
pxd rm -r /example/old-folder
pxd rm --permanent --yes /example/old.txt
```

Without flags `rm` moves nodes to the **trash**. A folder requires `-r`, like
unix; without it the command exits `2` with `IS_A_DIRECTORY`.

`--permanent` first trashes and then permanently deletes the node, its
descendants and their stored objects. That is irreversible:

- off a terminal it requires `--yes`, otherwise it exits `2` with
  `CONFIRMATION_REQUIRED` **before any network use**;
- on a terminal it asks with a confirm prompt.

Single (`--json`):

```json
{"ok":true,"node_id":"…","path":"/example/old.txt","permanent":false}
```

`--permanent` adds `"deleted_nodes":N,"deleted_objects":N`. Several paths use
`{"ok":true,"nodes":[{"node_id":"…","path":"…"}],"removed":N,"permanent":false}`.

### trash

```sh
pxd trash ls --json
pxd trash restore <id|name...> --json
pxd trash empty --yes --json
```

- `trash ls` lists every trashed node, most recently trashed first. Each item has
  `id`, `name`, `type`, `size`, `updated_at` and `deleted_at`.
- `trash restore` accepts ids and exact names. Names are resolved against the
  trash listing; a name shared by several trashed nodes is `AMBIGUOUS_NAME`
  (exit 2) with the candidate ids in `details.ids`. The server batch is
  all-or-nothing:

  ```json
  {"ok":true,"restored":[{"node_id":"…","name":"old.txt"}],"restored_count":1}
  ```

- `trash empty` permanently removes everything in the trash. It needs `--yes`
  off a terminal (`CONFIRMATION_REQUIRED`, exit 2, before any network use) and
  asks on a terminal.

  ```json
  {"ok":true,"deleted_nodes":2,"deleted_objects":2}
  ```

### url

```sh
pxd url /example/app.apk
pxd url /example/app.apk --inline --json
```

```json
{"ok":true,"url":"https://…/presigned…","expires_at":"2026-11-16T10:00:00Z"}
```

Prints a short-lived presigned download URL for a file (folders are `NOT_A_FILE`,
exit 2). Human/plain stdout is the bare URL so `curl "$(pxd url /file)"` works;
`--inline` signs `Content-Disposition: inline` for previews. The URL expires:
fetch a new one rather than caching it.

### link create

```sh
pxd link create /example/myapp/app-1.4.0.apk --expires 7d --json
printf '%s\n' "$LINK_PASSWORD" | pxd link create /docs --expires 24h --password-stdin --json
```

```json
{"ok":true,"id":"…","url":"https://personax-drive.cotc.dev/s/…","expires_at":"2026-11-16T10:00:00Z","has_password":false}
```

- `--expires` accepts `d`/`w` suffixes (`7d`, `2w`), any Go duration (`24h`,
  `90m`), or a future RFC3339 timestamp. Omit it for a link that never expires
  (`"expires_at":null`).
- `--password-stdin` reads the first line of stdin. There is deliberately **no
  `--password` flag** (it would leak through `ps` and shell history); an empty
  stdin is a usage error.
- **The `url` is shown once and cannot be retrieved again** — store it if you
  need it later.

### token

Personal access tokens are the recommended credential for agents and CI: they
are long-lived, do not rotate, and can be revoked individually.

```sh
pxd token create --name ci-android --expires 90d
pxd token ls --json
pxd token revoke ci-android
```

- `token create` requires a session from `pxd login`. It refuses environment
  credentials with exit `3` (`INTERACTIVE_SESSION_REQUIRED`): a CI or PAT
  credential must not be able to mint more secrets. The service is always
  `personax-drive`.
- `--expires` is a number of days with a `d` suffix (`1d`..`365d`, default
  `90d`) or `never`. The server also refuses names already used by an active
  token (`PAT_NAME_TAKEN`, exit 5) and more than 50 active tokens
  (`PAT_LIMIT_REACHED`, exit 5).
- **The token is printed exactly once** and cannot be retrieved again. Store it
  immediately as `PXD_TOKEN` in the CI secret store.

  ```json
  {"ok":true,"id":"…","name":"ci-android","token":"pxpat_…","display_prefix":"pxpat_abc12","expires_at":"2027-02-07T10:00:00Z"}
  ```

  `expires_at` is `null` for `never`.
- `token ls` never includes secrets, only `display_prefix`:

  ```json
  {"ok":true,"items":[{"id":"…","name":"ci-android","display_prefix":"pxpat_abc12","service":"personax-drive","expires_at":"…","last_used_at":null,"revoked_at":null,"created_at":"…"}],"total":1}
  ```

- `token revoke <id|name>` accepts a token id or the exact name of an active
  token. Ambiguous names exit `2` with the candidate ids; unknown names exit `4`.
  Revocation is immediate and idempotent:

  ```json
  {"ok":true,"id":"…","revoked":true}
  ```

- `pxd logout` cannot revoke a PAT. With `PXD_TOKEN` set it explains to use
  `pxd token revoke` and exits `2`.

## Credential sources

Resolution order, **first match wins**:

1. `PXD_TOKEN` — a personal access token (`pxpat_…`). Exchanged for a
   short-lived access token on first use via `POST /auth/token-exchange`, held
   **in memory only** and re-exchanged within 30 s of expiry or after a 401
   (single-flight, like a refresh). Nothing is written to disk. The prefix is
   validated locally, so a malformed value exits `3` (`PAT_INVALID`) without a
   network call; an unknown, revoked or expired token also exits `3` with
   "personal access token is invalid, expired or revoked". This is the
   agent/CI path.
2. `PXD_USERNAME` + `PXD_PASSWORD` — logs in at startup and keeps the token
   pair **in memory only** (nothing is written to disk). The session is logged
   out best-effort when the command exits. Setting only one of the two is a
   usage error (exit `2`). Still supported, but not recommended for CI now that
   PATs exist.
3. A stored session for the active profile + auth URL (from `pxd login`).
4. Nothing available — exit `3` with `error_code: "NOT_LOGGED_IN"`. `pxd` never
   prompts outside `pxd login` in an interactive terminal.

`PXD_TOKEN`, `PXD_USERNAME` and `PXD_PASSWORD` apply to every command that needs
authentication. `pxd token create|ls|revoke` are the exception: they require a
stored interactive session and refuse `PXD_TOKEN` and `PXD_USERNAME/PASSWORD`
with exit `3` (`INTERACTIVE_SESSION_REQUIRED`), so a CI secret cannot mint or
revoke more secrets. `pxd logout` with `PXD_TOKEN` set exits `2` and points at
`pxd token revoke`.

### Storage

Sessions are keyed by **profile name + auth URL**, so pointing a profile at a
different auth server never reuses a token minted elsewhere.

`PXD_CREDENTIALS_STORE` selects the backend:

| Value | Behaviour |
| --- | --- |
| `auto` (default) | Try the OS keyring; fall back to the file store when it is unavailable (e.g. headless Linux without a Secret Service). |
| `keyring` | OS keyring only (service `personax-cli`). |
| `file` | `$XDG_CONFIG_HOME/personax/credentials/<key-hash>.json` (fallback `~/.config/personax/credentials/`). The directory is `0700`, files are `0600`, writes are atomic. |

The backend actually used is reported as `store` by `pxd login` and as `source`
by `pxd whoami`.

Refresh tokens rotate on every use, and presenting an old one revokes the whole
session. `pxd` therefore refreshes with an in-process single-flight lock plus a
cross-process `flock`; after taking the lock it re-reads the store and adopts a
pair another `pxd` process already rotated. A revoked or expired refresh token
deletes the stored record and exits `3` with a message telling you to run
`pxd login` (or set `PXD_TOKEN` for automation).

PATs do not rotate, so `PXD_TOKEN` uses the same single-flight exchange but no
store and no cross-process lock: the exchanged access token lives in memory for
the duration of one command.

## Global flags

| Flag | Effect |
| --- | --- |
| `--json` | Machine-readable JSON on stdout. Takes priority over other modes. |
| `--plain` | No colour, spinners or prompts. |
| `--quiet` | Suppress progress and log output. |
| `--verbose` | Verbose diagnostics on stderr. |
| `--profile <name>` | Select a configuration profile. |

## Configuration

Path: `$XDG_CONFIG_HOME/personax/cli.toml`, falling back to
`~/.config/personax/cli.toml`. A missing file is not an error.

With no config file, `pxd` uses production
(`https://personax-drive.cotc.dev`, `https://personax-auth.cotc.dev`). Example
profile for a local stack:

```toml
[profiles.local]
drive_url = "http://localhost:4000"
auth_url  = "http://localhost:4001"
```

Precedence: **flags > environment > config file > built-in defaults**.

Selecting a profile other than `default` that is not defined in the config file
is a usage error: exit code `2` with `error_code: "UNKNOWN_PROFILE"` and
`details.config_path` / `details.profile`. The `default` profile may be absent,
in which case built-in defaults apply.

| Setting | Flag | Environment | Default |
| --- | --- | --- | --- |
| Profile | `--profile` | `PXD_PROFILE` | `default` |
| Drive URL | — | `PXD_DRIVE_URL` | `https://personax-drive.cotc.dev` |
| Auth URL | — | `PXD_AUTH_URL` | `https://personax-auth.cotc.dev` |

## Current limitations

- `PXD_TOKEN` personal access tokens are supported end to end; PATs are minted
  and revoked only from a stored interactive session.
- Interactive-TTY confirmations use a simple yes/no prompt; there is no
  `--dry-run` for `rm` or `trash empty`.
- No checksums are exposed by the API, so `--if-changed` and the download
  resume are size-based; a same-size change is not detected.
- Uploads and downloads are sequential per file with a bounded worker pool
  (`-j`); there is no multipart/resumable upload yet.
- The interactive TUI runs transfers three at a time (the CLI's `-j` default is
  four). Inline image previews need a Kitty-compatible terminal; set
  `PXD_TUI_NO_IMAGES=1` to disable them, `PXD_TUI_ASCII=1` for ASCII glyphs.
- The generated drive API client exists at `internal/driveapi`; `internal/driveapi/ops.go`
  wraps the parts the CLI uses with `internal/apierr` error mapping.
