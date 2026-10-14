---
name: remote-dev
description: Local-edit / remote-run workflow — code lives in a local folder (local Git) synced by mutagen to a server dir (no Git there); server commands run via `rdev` in a persistent herdr pane. Works for Claude Code and Codex alike; an agent delegated by another (e.g. Codex via the Claude Code codex plugin) only edits code locally. Use when the project (or a parent dir) has `.remote-dev.toml`, when rdev/mutagen/herdr report sync/network problems, or when the user asks to create/initialize a project synced to an SSH server, set up mutagen + herdr for a server directory, or migrate a server-side Git project (新建远程项目 / 同步到服务器 / 服务器上的某个目录 / mutagen / herdr / rdev).
---

# Remote dev (mutagen + herdr + local Git)

For **creating or migrating a project**, read `references/setup.md` and follow it. Everything below is for daily work inside a project that has `.remote-dev.toml`.

## Rules

- **Edit locally.** mutagen syncs the folder to `remote_path`. Never scp/rsync code; never ssh to the host (a hook denies it).
- **Run server commands with `rdev '<cmd>'`** — single quotes, so `$VERSION` etc. expand on the server. rdev checks/flushes the sync, injects local Git metadata, runs in the dedicated herdr workspace `rdev-<name>` on the server, prints the output and exits with the remote exit code.
- **Git is local only.** The server has no `.git`; never run git there. Commit/push from the local repo.
- **Roles.** The *main* agent (whichever of Claude Code or Codex the user is talking to) runs `rdev` and owns Git. A *delegated* agent — Codex started by Claude Code through the codex plugin / `codex:rescue` (its environment has `CLAUDECODE` or `CODEX_COMPANION_SESSION_ID`) — edits code locally only and never runs `rdev`/mutagen/herdr/ssh; a hook denies `rdev` there. The main agent verifies with `rdev` and feeds errors back.
- Toolchains on the server may not be on PATH; prefer the project's own wrapper scripts (e.g. `scripts/dev.sh test`) over bare tool names.

## rdev

```bash
rdev 'go test ./...'                    # wait (default --timeout 1800), print last 300 lines
rdev --bg './scripts/dev.sh run'        # long-lived or > ~8 min: returns a token immediately
rdev --wait TOKEN --timeout 540         # collect / keep waiting (repeat as needed)
rdev --log TOKEN --lines 1000
rdev up                                 # check & repair sync, herdr, pane; list uncollected jobs
rdev --clear-stale                      # busy markers left by crashed runs
```

- Shell tool calls may time out (Claude Code's Bash tool caps at 10 minutes). For anything that may run longer, start it with `--bg`, then `rdev --wait TOKEN --timeout 540` in a loop.
- One command at a time per project (pane busy → refused). `--force` only when the user agrees.
- Files generated on the server (gofmt, codegen, lockfiles) sync back; review them with local `git status`.

## Exit codes and what to do

| code | meaning | action |
|---|---|---|
| remote code | command finished | normal handling |
| 2 | config / herdr server problem | read the message; if it says `herdr machine add` or `reconnect`, ask the **user** to run it in their terminal |
| 3 | sync offline / halted | network is down or reconnecting. Keep editing locally; retry `rdev up` later. Don't run anything on stale code |
| 4 | sync conflicts | show `mutagen sync list <session>`; ask the user which side wins |
| 124 | still running after --timeout | `rdev --wait TOKEN` |
| 125 | server unreachable mid-run | the job **keeps running on the server**. Do NOT re-run it. When back online: `rdev up`, then `rdev --wait TOKEN` |

## Network changes / laptop sleep

The agent session survives; ssh connections don't. Remote jobs keep running in the server-side herdr pane. Hooks tell you about trouble:
- At session start, the context includes `rdev up` status.
- Before each user turn, a local-only check reports a disconnected sync, conflicts, or uncollected jobs (silent when healthy).

On such a notice: run `rdev up`; collect listed jobs with `rdev --wait TOKEN` instead of re-running them; keep working locally while offline. Never run `herdr machine reconnect` / `machine add` yourself — they need the user's interactive SSH auth.
