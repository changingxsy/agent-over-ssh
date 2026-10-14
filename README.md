# tether

**Edit locally, run remotely.** A small toolkit that lets you (and coding agents such as Claude Code or Codex) work on a project whose code lives on your laptop but builds and runs on an SSH server.

[简体中文](README.zh-CN.md)

```
 laptop                                         server
┌───────────────────────────┐   mutagen    ┌──────────────────────────┐
│ ~/work/myproj  (Git here) │ ◀──────────▶ │ /srv/myproj  (no .git)   │
│                           │  two-way-safe│                          │
│ rdev 'go test ./...' ─────┼──── herdr ──▶│ herdr workspace          │
│   ◀── output + exit code ─┼──────────────│   rdev-myproj (pane)     │
└───────────────────────────┘              └──────────────────────────┘
```

- **[mutagen](https://mutagen.io)** keeps the local folder and the server directory in sync.
- **[herdr](https://herdr.dev)** keeps a persistent pane on the server, so long jobs survive laptop sleep and network changes.
- **Git stays local.** The server copy has no `.git`; version info is injected into every run.
- **`rdev`** ties it together: check & flush the sync, run the command in the pane, stream back output and the remote exit code.

## Why

Agents and editors work best on local files, but the toolchain, data or GPU is on the server. Running commands over plain `ssh` breaks on every Wi‑Fi change, and keeping Git on both sides invites divergence. tether makes the server a pure execution target:

- `rdev` refuses to run on stale code: it waits for the sync to connect and flushes it first.
- A command that is running when the network drops **keeps running** on the server; `rdev --wait TOKEN` collects it later instead of re-running it.
- Hooks for Claude Code / Codex inject the sync status at session start, warn about conflicts or uncollected jobs, and block direct `ssh`/`scp` to the dev host.

## Requirements

- macOS (tested) or Linux (untested), `bash`, `jq`, `perl`, OpenSSH with a host alias in `~/.ssh/config`
- [mutagen](https://mutagen.io/documentation/introduction/installation) on the laptop
- [herdr](https://herdr.dev) on the laptop, with the server added via `herdr machine add <host>`

## Install

```bash
git clone https://github.com/changingxsy/tether.git ~/src/tether
~/src/tether/install.sh
```

`install.sh` symlinks `rdev` and `remote-dev-init` into `~/.local/bin` (override with `BIN_DIR`) and the agent skill into `~/.claude/skills` / `~/.codex/skills`. It never overwrites existing files. Hooks are opt-in: merge [`examples/claude-settings.hooks.json`](examples/claude-settings.hooks.json) into `~/.claude/settings.json` and/or [`examples/codex-hooks.json`](examples/codex-hooks.json) into `~/.codex/hooks.json`, replacing `/path/to/tether`.

## Quick start

```bash
# preview (read-only), then create: local repo + remote dir + mutagen session
remote-dev-init --host devbox --remote /srv/myproj --stack go --plan
remote-dev-init --host devbox --remote /srv/myproj --stack go

cd ~/work/myproj
rdev 'go test ./...'                  # run and wait; exits with the remote exit code
rdev --bg './scripts/run-server.sh'   # long-running: prints a TOKEN immediately
rdev --wait TOKEN --timeout 540       # collect it (repeat as needed)
rdev up                               # check / repair sync, herdr pane, uncollected jobs
```

`remote-dev-init --migrate-server-git` moves an existing server-side Git checkout to your laptop (the server `.git` is renamed, not deleted, and only after checking it is clean and pushed). See [`skills/remote-dev/references/setup.md`](skills/remote-dev/references/setup.md).

Per-project configuration lives in `.remote-dev.toml` ([example](examples/remote-dev.toml.example)), which is excluded from Git.

## Exit codes

| code | meaning |
|---|---|
| remote code | the command finished |
| 2 | config or herdr problem (message says what to run) |
| 3 | sync offline or halted — keep editing locally, retry later |
| 4 | sync conflicts — resolve with `mutagen sync list <session>` |
| 124 | still running after `--timeout` — `rdev --wait TOKEN` |
| 125 | server unreachable mid-run — the job keeps running; `rdev up && rdev --wait TOKEN` |

## Build metadata without Git on the server

Every `rdev` run exports `VERSION` (`git describe --tags --always --dirty`), `COMMIT`, `COMMIT_FULL`, `BUILD_DATE` and `SOURCE_DIRTY`, and writes `.build-meta.json` / `.build-meta.files` into the synced tree for builds that are not started by `rdev`.

## Using with coding agents

[`skills/remote-dev/SKILL.md`](skills/remote-dev/SKILL.md) is an agent skill (Claude Code / Codex format) describing the workflow and the exit-code playbook. With the hooks installed:

| hook | what it does |
|---|---|
| `SessionStart` | runs `rdev up --quiet` and injects the status + rules |
| `UserPromptSubmit` | local-only check; speaks up only on disconnect, conflicts or uncollected jobs |
| `PreToolUse` | denies `ssh`/`scp`/`sftp` to the dev host; a Codex agent delegated by Claude Code may not run `rdev`/`mutagen`/`herdr` |

## Tests

```bash
tests/run-guard-tests.sh
```

## License

[MIT](LICENSE)
