# Command routing

English · [简体中文](zh-CN/command-routing.md) · [Docs index](../README.md#documentation)

The agent never needs to know *where* a command runs. It edits files locally and calls `rdev '<cmd>'`; the layers below handle the sync, remote execution and recovery.

## What `rdev` does

Each `rdev '<cmd>'`:

1. **Finds the project.** It searches `.remote-dev.toml` upward from the current directory and maps the local subdirectory to the same one on the server.
2. **Checks the sync.** Waits while mutagen is connecting (`wait_sync`, 30 s by default), resumes it if paused, then flushes. It **refuses to run** on conflicts or an offline sync, so nothing ever runs on stale code.
3. **Finds the pane.** Finds or creates the herdr workspace `rdev-<name>` on the server (cwd = the remote project dir). One command per project at a time; a busy pane is refused.
4. **Submits the run.** Uploads a small script with the command plus the version variables to `~/.rdev/run/<name>/<TOKEN>.sh` and runs it in the pane, which records the log and exit code on the server.
5. **Waits and streams back.** Prints the output (last 300 lines by default) and exits with the remote exit code. During a network loss it keeps retrying for up to `net_wait` seconds (300 by default); the job keeps running on the server either way.
6. **Flushes again**, so files generated on the server come back to your laptop.

Quote the command in single quotes — `rdev 'echo $VERSION'` — so variables expand on the server.

## Where each command runs

| kind of command | examples | runs on | enforced by |
|---|---|---|---|
| reading / writing code, searching | the agent's file tools, `rg`, `grep` | laptop | that's where the files are; mutagen syncs them |
| Git | `git commit`, `git push` | laptop | the server has no `.git`; the rules say so too |
| builds, tests, training — anything that needs the server's environment | `rdev 'pytest'`, `rdev --bg 'python train.py'` | server | **rules** injected by the session hook and stated in the skill |
| direct `ssh` / `scp` / `sftp` to the dev host | `ssh devbox ...` | blocked | **hard block** in the `PreToolUse` hook, pointing to `rdev` |
| a delegated agent running `rdev` / `mutagen` / `herdr` | Codex invoked by Claude Code | blocked | **hard block**: delegated agents only edit |

### What if the agent runs a server command locally by mistake?

It is not blocked; this category relies on the rules. From the first turn the agent's context says "run server commands with `rdev '<cmd>'`" along with the current sync status, and the skill repeats it. In practice the laptop usually lacks the server's data, GPU or toolchain, so such a command fails locally and the agent switches to `rdev`. If your laptop does have the same environment and the difference matters, add your own block — see [Agent integration → Customizing](agent-integration.md#customizing-the-hooks).

## Long jobs

Agent tool calls have time limits (Claude Code's Bash tool caps at 10 minutes). For anything that may run longer, start it in the background and collect it in chunks:

```bash
rdev --bg 'python train.py'          # prints a TOKEN immediately
rdev --wait TOKEN --timeout 540      # wait up to 9 min; repeat while it exits 124
rdev --log TOKEN --lines 1000        # read more of the log at any time
```

A plain `rdev '<cmd>'` waits up to `--timeout` (1800 s by default) and exits 124 if the command is still running; the job continues and can be collected with `--wait`.

**Watching live.** The command runs in a real terminal pane, so you can look at it whenever you like: open the server's herdr session (for example `herdr --remote devbox`) and switch to the `rdev-<name>` workspace. Logs are also kept on the server in `~/.rdev/run/<name>/<TOKEN>.log`.

**One at a time.** A project's pane runs one command at a time; a second `rdev` is refused while the first is running. `--force` skips that check (only when you are sure), and `rdev --clear-stale` removes busy markers left behind by crashed runs.

## Network loss and laptop sleep

The agent session survives on the laptop; SSH connections do not. What happens:

- A running command **keeps running** in the server-side pane.
- A waiting `rdev` keeps retrying for `net_wait` seconds, then exits 125 with the token.
- Local edits are queued by mutagen and synced on reconnect.
- `rdev` keeps a local record of started jobs (`~/.cache/rdev/<name>.jobs`), so `rdev up` lists jobs that finished or are still running but were never collected, and the prompt hook tells the agent about them.

Recovery is always the same: `rdev up`, then `rdev --wait TOKEN` — **not** re-running the command.

## Exit codes

| code | meaning | what to do |
|---|---|---|
| remote code | the command finished | normal handling |
| 2 | config or herdr problem | read the message; if it says `herdr machine add` / `reconnect`, run that in your own terminal |
| 3 | sync offline or halted | keep editing locally; retry `rdev up` later |
| 4 | sync conflicts | `mutagen sync list <session>`, decide which side wins |
| 124 | still running after `--timeout` | `rdev --wait TOKEN` |
| 125 | server unreachable mid-run | the job keeps running; `rdev up && rdev --wait TOKEN` |
