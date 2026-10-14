# Agent integration

English · [简体中文](zh-CN/agent-integration.md) · [Docs index](../README.md#documentation)

`rdev` is a plain CLI that any agent or human can use. For Claude Code and Codex, a skill and a set of hooks make the agent follow the workflow without being reminded.

Both only act inside projects that contain `.remote-dev.toml`; every other directory is untouched.

## The skill

`install.sh` links [`skills/remote-dev`](../skills/remote-dev/SKILL.md) into `~/.claude/skills` and (if present) `~/.codex/skills`. It tells the agent:

- edit locally; run every server-side command with `rdev '<cmd>'`; Git is local only;
- use `--bg` / `--wait` for anything that may outlive a tool call;
- what each exit code means and what to do about it (never re-run a job after exit 125);
- how to set up or migrate a project with `remote-dev-init` ([`references/setup.md`](../skills/remote-dev/references/setup.md)).

## The hooks

Hooks are opt-in. Merge [`examples/claude-settings.hooks.json`](../examples/claude-settings.hooks.json) into `~/.claude/settings.json` and/or [`examples/codex-hooks.json`](../examples/codex-hooks.json) into `~/.codex/hooks.json`, replacing `/path/to/agent-over-ssh`.

| hook | what it does |
|---|---|
| `SessionStart` | runs `rdev up --quiet` and injects the real sync / herdr status plus the workflow rules into the agent's context |
| `UserPromptSubmit` | a local-only check before each turn (no server contact); speaks up only on a disconnected sync, conflicts or uncollected jobs |
| `PreToolUse` | hard-blocks direct `ssh` / `scp` / `sftp` to the dev host, and `rdev` / `mutagen` / `herdr` in delegated agents |

## Main and delegated agents

The **main** agent — whichever of Claude Code or Codex you are talking to — runs `rdev` and owns Git.

A **delegated** agent — Codex started by Claude Code through the Codex plugin, recognized by `CLAUDECODE` or `CODEX_COMPANION_SESSION_ID` in its environment — only edits code locally. Its session hook injects "edit only" rules, and its `PreToolUse` hook denies `rdev`, `mutagen` and `herdr`. The main agent verifies the result with `rdev` and feeds errors back. This keeps a single owner for the pane, the sync and Git.

## Customizing the hooks

Every hook is a plain bash script on your laptop ([`hooks/rdev-hook.sh`](../hooks/rdev-hook.sh)), referenced from your own settings; nothing is configured remotely. If a rule gets in your way, or you want stricter limits, edit it:

- **Relax:** adjust the patterns in the `guard` branch, or drop a hook from your settings.
- **Tighten:** add your own deny rules in the `guard` branch — for example, block local `python train.py` or `torchrun` — returning `permissionDecision: "deny"` with a hint to use `rdev`.
- **Test:** add examples to [`tests/guard-cases.txt`](../tests/guard-cases.txt) (lines before `#EXPECT-DENY` must be allowed, lines after it denied) and run `tests/run-guard-tests.sh`.

Changes apply on the next tool call or session. Keeping your edits on a branch of your fork makes upstream updates easy to merge.
