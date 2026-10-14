# Setting up a remote-dev project

Tool: `remote-dev-init` (not auto-approved on purpose — the user sees each run in a permission prompt).

```
remote-dev-init --host H --remote /abs/path [--dir ~/work/NAME] [--name NAME]
                [--stack go,node,python] [--machine LABEL] [--migrate-server-git] [--plan]
                [--ignore PATTERN]...
```

## Procedure

1. **Collect parameters.** Ask only for what is missing:
   - `--host`: an SSH alias. If unsure, list `Host` entries from `~/.ssh/config` and let the user pick.
   - `--remote`: absolute project directory on the server (not `/`, not a home dir itself).
   - `--dir`: defaults to `~/work/<basename of remote>`.
   - `--stack`: decides extra mutagen ignores / initial `.gitignore` (go: `/bin /dist`; node: `node_modules /dist /build /.next /coverage`; python: `__pycache__ .venv venv *.pyc ...`).
   - `--ignore` (repeatable): paths that stay **server-only** and are never synced — datasets, model weights, checkpoints, experiment outputs, logs. Only lightweight code should come to the laptop, so ask the user which large directories exist (for an existing remote dir, look at its top-level sizes with the user) and confirm the list; changing it later means recreating the mutagen session.
   Authorization: a user request to "create/initialize a project" counts as approval for `git init` in that new directory. Do not `git init` anywhere else.
2. **Plan (read-only):** `remote-dev-init ... --plan`. Show the user the mode and actions:
   - `new` — remote dir missing/empty: `mkdir -p` remote, `git init` + initial commit locally, config, mutagen.
   - `migrate` — remote dir has `.git`: needs `--migrate-server-git` and the user's explicit OK (it renames the server `.git`; reversible with `mv`). Pre-checks refuse unless the server repo is clean, has no stash, and all branches are pushed.
   - `resume` — earlier run was interrupted; finishes remaining steps.
   - Refusals (exit 10): remote has files but no Git; local `--dir` non-empty without Git. Report them and ask the user how to proceed; don't work around them.
3. **Run** the same command without `--plan`. It is idempotent; re-run after fixing any blocker.
4. **Exit 20** = herdr machine not saved. Ask the user to run `herdr machine add <host>` in their own terminal (interactive SSH auth, may install herdr on the server), then re-run.
5. **Report**: local dir, remote path, mutagen session name, herdr workspace `rdev-<name>`, initial commit. Mention that pushing / creating a GitHub remote was not done.

## What it creates

- Local: Git repo, `.remote-dev.toml` (host, machine, remote_path, mutagen, name), excludes in `.git/info/exclude` for `.remote-dev.toml`, `.remote-dev.ignores`, `.build-meta.json`, `.build-meta.files`.
- mutagen session `<name>`, `two-way-safe`, `--ignore-vcs`, ignores = common (`.DS_Store /.claude /.codex .env .git.migrated-* ...`) + stack + `--ignore` paths + (migration) every path the server's Git ignored; the last two are saved in `.remote-dev.ignores`.
- Server: the directory, and on first `rdev` use a herdr workspace `rdev-<name>` with cwd = remote dir.

## Version metadata (no Git on the server)

Each `rdev` run exports from the local repo: `VERSION` (`git describe --tags --always --dirty`, or `dev`), `COMMIT` (short, `-dirty` suffix), `COMMIT_FULL`, `BUILD_DATE` (UTC), `SOURCE_DIRTY`; and writes synced `.build-meta.json` / `.build-meta.files` (NUL-separated `git ls-files --cached --others --exclude-standard -z`) for builds not started by rdev.

Project conventions to apply when scripts need version info:
- Shell: `VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"`.
- Go: `go build -buildvcs=false -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE"`.
- Anything that calls git directly: fall back to `.build-meta.*` when `.git` is absent. During a migration, grep the project scripts for `git ` — failures can be silent (e.g. `git ls-files | xargs gofmt` formats nothing).

## Removing a test/abandoned setup (only when the user asks)

`mutagen sync terminate <session>`; `herdr --machine <m> workspace close <id of rdev-<name>>`; delete the local and remote dirs only with explicit approval; `rm ~/.cache/rdev/<name>.*`.
