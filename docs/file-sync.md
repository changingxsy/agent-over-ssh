# File routing

English · [简体中文](zh-CN/file-sync.md) · [Docs index](../README.md#documentation)

mutagen keeps the project directory on your laptop and the one on the server in sync — but only the lightweight part. Heavy files stay on the server, so your laptop holds just what the agent needs to read and edit.

## What goes where

| synced (both sides) | server-only | laptop-only |
|---|---|---|
| source, configs, scripts, docs, small test fixtures | datasets, model weights, checkpoints, experiment outputs, logs, virtualenvs, build artifacts | `.git`, agent config and credentials, `.remote-dev.toml`, `.remote-dev.ignores` |

Server-only and laptop-only paths are simply **not synced**; they are never deleted on either side.

## Choosing server-only paths

You decide this when creating the project:

```bash
remote-dev-init --host gpu1 --remote /data/me/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs --ignore '*.ckpt' --plan
```

- **Always ignored:** `.DS_Store`, `/.claude`, `/.codex`, `/.remote-dev.toml`, `/.remote-dev.ignores`, `.env`, `.git.migrated-*`. (`.env` is ignored, so each side keeps its own.)
- **`--stack`** adds common artifacts (comma-separated):
  - `go`: `/bin /dist`
  - `node`: `node_modules /dist /build /.next /coverage`
  - `python`: `__pycache__ .venv venv *.pyc .pytest_cache .mypy_cache`
- **`--ignore PATTERN`** (repeatable) adds your project's own large paths, in [mutagen ignore syntax](https://mutagen.io/documentation/synchronization/ignores): `/data` means `data` at the project root; `*.ckpt` matches anywhere.
- When migrating a server-side Git repo, everything that repo's `.gitignore` ignored becomes server-only automatically.

`--ignore` paths and migrated ignores are recorded in `.remote-dev.ignores`. For a brand-new repo, the whole list (minus the `.remote-dev*` files) also becomes the initial `.gitignore`.

> For an existing server directory, look at its top-level sizes first (`du -sh *` on the server) and decide which directories should never come to your laptop. Changing the list later means recreating the sync session.

### Changing the list later

```bash
mutagen sync terminate myproj
mutagen sync create --name myproj --mode two-way-safe --ignore-vcs \
  --ignore .DS_Store --ignore /.claude --ignore /.codex --ignore /.remote-dev.toml \
  --ignore /.remote-dev.ignores --ignore .env --ignore '.git.migrated-*' \
  --ignore <stack and project paths...> \
  ~/work/myproj devbox:/srv/myproj
```

Then update `.remote-dev.ignores` to match, so a later `remote-dev-init` re-run uses the same list. Nothing is deleted by terminating a session.

## How the sync behaves

- **Mode `two-way-safe`.** Edits flow both ways; when both sides changed the same file, mutagen records a conflict instead of picking a winner. `rdev` refuses to run while conflicts exist (exit 4); inspect them with `mutagen sync list myproj` and decide which side wins.
- **VCS directories are ignored** (`--ignore-vcs`), so `.git` never reaches the server.
- **Server-generated files come back.** After each run `rdev` flushes once more, so formatting, code generation or lockfile updates done on the server appear in your local working tree — review them with `git status`.
- **Offline edits are queued.** If the network drops, keep editing; mutagen catches up when it reconnects, and `rdev` waits for that before running anything.

## Creating or migrating a project

`remote-dev-init` probes both sides and picks a mode:

| mode | when | what it does |
|---|---|---|
| `new` | remote dir missing or empty | `mkdir -p` on the server, `git init` + initial commit locally, write `.remote-dev.toml`, create the mutagen session |
| `migrate` | remote dir has `.git` (needs `--migrate-server-git`) | verify the server repo is clean, has no stash and every branch is pushed; copy `.git` to the laptop (rsync) and check it out; record the server's ignored files as server-only; rename the server `.git` to `.git.migrated-<date>`; create the session |
| `resume` | an earlier run was interrupted | finish the remaining steps |

It refuses (exit 10) instead of guessing when the remote dir has files but no Git, or when the local directory is non-empty without Git. Every step checks whether it is already done, so re-running is safe. To undo a migration, `mv .git.migrated-<date> .git` on the server.

`--plan` prints the mode and planned actions without changing anything. If the herdr machine is not saved yet, it exits 20 and asks you to run `herdr machine add <host>` in your own terminal (interactive SSH auth), then re-run.

## Build metadata without Git on the server

Every `rdev` run exports these variables from the local repo:

| variable | value |
|---|---|
| `VERSION` | `git describe --tags --always --dirty`, or `dev` |
| `COMMIT` | short hash, with `-dirty` when the tree has changes |
| `COMMIT_FULL` | full hash |
| `BUILD_DATE` | UTC, ISO 8601 |
| `SOURCE_DIRTY` | `true` / `false` |

It also writes two synced files for builds not started by `rdev`:

- `.build-meta.json` — `{"version", "commit", "commit_full", "dirty"}`
- `.build-meta.files` — NUL-separated list of tracked and untracked-but-not-ignored files (`git ls-files --cached --others --exclude-standard -z`)

Both are excluded from Git via `.git/info/exclude`. Conventions for project scripts:

- Shell: `VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"`
- Go: `go build -buildvcs=false -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE"`
- Anything that calls `git` directly should fall back to `.build-meta.*` when `.git` is absent. After a migration, grep your scripts for `git ` — such failures can be silent (e.g. `git ls-files | xargs gofmt` formats nothing).
