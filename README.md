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

## What is wrapped: routing commands

tether's core is hiding *where* things run. The agent only edits code locally and calls `rdev`; the layers below handle sync, remote execution and recovery.

### 1. `rdev`: the single entry point for remote execution

Each `rdev '<cmd>'`:

1. Finds `.remote-dev.toml` upward from the current directory and maps the local subdirectory to the matching one on the server.
2. Checks the mutagen sync: waits if it is connecting (30 s by default), resumes it if paused, then flushes. It **refuses to run** on conflicts or an offline sync, so nothing runs on stale code.
3. Finds or creates the herdr workspace `rdev-<name>` on the server. One command per project at a time; a busy pane is refused.
4. Injects version info from local Git (`VERSION`, `COMMIT`, …), runs the command in the pane, and records its log and exit code on the server.
5. Waits and streams back the output. During a network loss it keeps retrying for up to `net_wait` seconds; the job keeps running on the server and can be collected later by its TOKEN.
6. Flushes once more so files generated on the server (formatting, codegen, lockfiles) come back to your laptop.

### 2. Where each command runs

| kind of command | examples | runs on | enforced by |
|---|---|---|---|
| reading/writing code, searching | the agent's file tools, `rg`, `grep` | laptop | that's where the files are; mutagen syncs them |
| Git | `git commit`, `git push` | laptop | the server has no `.git`, so Git cannot run there; the rules say so too |
| builds, tests, training — anything that needs the server's environment | `rdev 'pytest'`, `rdev --bg 'python train.py'` | server | **rules**: injected by the session hook and stated in the skill (see below) |
| direct `ssh`/`scp`/`sftp` to the dev host | `ssh devbox ...` | blocked | **hard block**: the PreToolUse hook denies it and points to `rdev` |
| a delegated agent running `rdev`/`mutagen`/`herdr` | Codex invoked by Claude Code | blocked | **hard block**: delegated agents only edit; the main agent verifies with `rdev` |

Hooks only act inside projects that contain `.remote-dev.toml`; every other directory is untouched.

| hook | what it does |
|---|---|
| `SessionStart` | runs `rdev up --quiet` and injects the sync/herdr status and the rules above; a delegated agent gets "edit only" rules instead |
| `UserPromptSubmit` | a local-only check before each turn (no server contact); speaks up only on disconnect, conflicts or uncollected jobs |
| `PreToolUse` | the two hard blocks in the table |

### 3. What if the agent runs a server command locally by mistake?

It is **not blocked** today; this category relies on the rules:

- From the first turn, the agent's context says "run server commands with `rdev '<cmd>'`" along with the current sync status, and [`SKILL.md`](skills/remote-dev/SKILL.md) repeats it with an exit-code playbook.
- The laptop usually lacks the server's data, GPU or toolchain (those are server-only by design), so such a command tends to fail locally and the agent switches to `rdev`.
- If your laptop happens to have the same environment, the command will run locally and may give different results. If that matters for your project, add your own block as described next.

## Customizing: the hooks are code on your machine

Every hook is a plain bash script on your laptop ([`hooks/rdev-hook.sh`](hooks/rdev-hook.sh)), referenced from your own `~/.claude/settings.json` / `~/.codex/hooks.json`; nothing is configured remotely. If a rule gets in the way of a command you need, or you want stricter limits, edit it:

- **Relax**: adjust the patterns in the `guard` branch, or drop the hook from your settings.
- **Tighten**: add your own deny rules in the `guard` branch — e.g. block local `python train.py` or `torchrun` — returning `permissionDecision: "deny"` with a hint to use `rdev`.
- **Test**: add examples to [`tests/guard-cases.txt`](tests/guard-cases.txt) (lines before `#EXPECT-DENY` must be allowed, lines after it denied) and run `tests/run-guard-tests.sh`.
- Changes apply on the next tool call or session; nothing to restart. Keeping your edits on a branch of your fork makes upstream updates easy to merge.

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

## Tests

```bash
tests/run-guard-tests.sh
```

## License

[MIT](LICENSE)
