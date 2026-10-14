# tether

**Connect your local AI agents to any server — over SSH alone.** Agents, credentials and Git stay on your machine; the server only runs code, reached through a single SSH port.

[简体中文](README.zh-CN.md)

```
laptop: Claude Code / Codex · API keys · Git token · MCP · ~/work/myproj (Git)
  │
  │  SSH (the only port used, no port forwarding)
  │   ├─ mutagen: syncs the code; datasets and models stay on the server
  │   └─ herdr  : rdev 'python train.py' runs in a persistent pane, survives
  │               network loss, streams output and exit code back
  ▼
server: /srv/myproj (no .git, no credentials, just runs code)
```

## Why tether

Research and development often means juggling several servers: a lab GPU box, a university cluster, a cloud VM. Letting an AI agent work directly on each of them means installing, logging in and configuring Claude Code / Codex, API keys, Git credentials, MCP servers, skills and preferences on every machine — all things that are already set up on your laptop. Repeating that remotely is tedious, and it puts your credentials on machines someone else administers.

tether turns it around: **the agent stays local, the server is only an execution target, and the two talk over SSH only.**

- **Credentials never leave your machine.** API keys, agent logins, Git/GitHub tokens and MCP configs exist only locally. The server holds the project code plus two helper binaries that mutagen and herdr deploy over SSH (neither carries credentials). On a shared server, other users and admins never get near your keys.
- **Works wherever SSH works.** Many servers forbid port forwarding, expose no extra ports, or have no outbound internet, which rules out setups where an agent connects through a forwarded port. tether's sync (mutagen) and remote execution (herdr) both start a helper on the server over SSH and talk to it over stdin/stdout — **no port forwarding, no extra open ports**. If you can log in, you can use it.
- **Configure once, reuse everywhere.** Adding a server takes one alias in `~/.ssh/config` and one `remote-dev-init`; your local agent setup is reused as is.
- **Full coordination on top of one SSH link.** Sync, remote execution, surviving disconnects, version metadata and agent guardrails all run over that connection:
  - `rdev` refuses to run on stale code: it waits for the sync to connect and flushes it first.
  - A command running when the network drops or the lid closes **keeps running** on the server; `rdev --wait TOKEN` collects it later instead of re-running it.
  - Git stays local; the server has no `.git`, so the two sides cannot diverge. Version info is injected into every run.
  - Hooks for Claude Code / Codex inject the sync status at session start, warn about conflicts or uncollected jobs, and block direct `ssh`/`scp` to the dev host.

## What lives where

tether brings only the **lightweight code** to your laptop; large files stay on the server and are never synced. So during setup you decide which paths are synced and which stay server-only:

| synced (both sides) | server-only (exclude with `--ignore`) | local only |
|---|---|---|
| source, configs, scripts, docs, small test fixtures | datasets, model weights, checkpoints, experiment outputs, logs, virtualenvs, build artifacts | `.git`, agent config and credentials, `.remote-dev.toml` |

```bash
remote-dev-init --host gpu1 --remote /data/me/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs --ignore '*.ckpt' --plan
```

- `--stack` excludes common artifacts (e.g. `.venv`, `__pycache__` for python); `--ignore` adds your project's own large paths, in mutagen ignore syntax (`/data` means `data` at the project root).
- When migrating an existing server-side Git project (`--migrate-server-git`), everything that repo's `.gitignore` ignored becomes server-only automatically.
- Excluded paths are never deleted on either side, just not synced. To change the list after setup, recreate the mutagen session: `mutagen sync terminate <name>`, then `mutagen sync create` with the new ignores (see step 3 of `remote-dev-init`), and update `.remote-dev.ignores`.

## Components

- **[mutagen](https://mutagen.io)** — two-way-safe sync of the local folder and the server directory, over SSH.
- **[herdr](https://herdr.dev)** — a persistent pane on the server, over SSH; jobs survive laptop sleep and network changes.
- **`rdev`** — check & flush the sync, run the command in the pane, stream back output and the remote exit code.
- **`remote-dev-init`** — set up or migrate a project.
- **hooks + skill** — make Claude Code / Codex follow this workflow.

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
