# FAQ

English · [简体中文](zh-CN/faq.md) · [Docs index](../README.md#documentation)

### How is this different from VS Code Remote-SSH?

Remote-SSH runs the editor's backend and its workspace extensions on the server, so an AI extension there needs its own installation, login and network access on every host. agent-over-ssh keeps the agent entirely on the laptop and gives it two narrow channels to the server: synced files and `rdev`. You can still use any editor locally — the files are ordinary local files.

### Why not just install Claude Code or Codex on the server?

You can, but then every server needs the agent, its login, API keys, Git credentials, MCP servers and skills — and outbound internet to reach the model API. Servers change often, some have no internet, and shared ones put your credentials where others can reach them. Here you configure the agent once, on your laptop, and adding a server is one SSH alias plus one `remote-dev-init`.

### Why not sshfs, or rsync?

- **sshfs** makes every file access a network round trip; agents read and search a lot of files, which gets slow, and the mount breaks when the network does. You would still need a way to run commands.
- **rsync** is one-way and manual: nothing tells you when the server copy is stale, and nothing detects conflicting edits. mutagen syncs continuously in both directions, and `rdev` refuses to run until the sync is flushed and conflict-free.

### Does the server need internet access or open ports?

No. Only SSH. The mutagen and herdr helpers are deployed to the server over SSH from the laptop, and both talk over the SSH session itself. Your project's own commands may of course need internet (e.g. `pip install`).

### Does it work inside containers?

Yes, as long as you can SSH into the container (or into a host where the project directory lives). No ports beyond SSH are needed.

### What happens when the network drops or I close the lid?

Running commands keep running on the server. Local edits are queued and synced on reconnect. `rdev up` then lists jobs that were never collected, and `rdev --wait TOKEN` collects them. See [Command routing → Network loss](command-routing.md#network-loss-and-laptop-sleep).

### Can I watch what a command is doing?

Yes. Commands run in a real terminal pane: open the server's herdr session (e.g. `herdr --remote devbox`) and switch to the `rdev-<name>` workspace. `rdev --log TOKEN` prints the log from the laptop.

### Can I use several servers?

Yes. Each project points to one server directory; different projects can use different servers, and one server can host several projects (each gets its own workspace `rdev-<name>`). A single project cannot target two servers at once — create a second project for that.

### Can I run several commands at once?

One at a time per project: the pane is refused while busy, which keeps outputs and exit codes unambiguous. Start long jobs with `--bg`; for parallel work, split it inside the command (e.g. a script that launches several processes).

### Does it only work with Claude Code and Codex?

`rdev` and `remote-dev-init` are plain CLIs; any agent that can run shell commands, or you yourself, can use them. The skill and hooks are written for Claude Code and Codex.

### Which platforms are supported?

The laptop side is tested on macOS and should work on Linux (untested). Windows is not supported natively. The server needs SSH and `bash`.

### What ends up on the server?

The synced project code, your server-only data, a herdr workspace, run logs under `~/.rdev/run/<name>/`, and the mutagen / herdr helper binaries. No `.git`, no keys, no tokens.
