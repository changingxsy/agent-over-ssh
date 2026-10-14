# agent-over-ssh

**Keep your AI coding agents and credentials on your laptop, and let any server just run the code — over plain SSH.**

[![ci](https://github.com/changingxsy/agent-over-ssh/actions/workflows/ci.yml/badge.svg)](https://github.com/changingxsy/agent-over-ssh/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

English · [简体中文](README.zh-CN.md)

## The problem

**Servers change, and every one needs the agent set up again.** Research and development usually happen on servers — a lab GPU box, a university cluster, a cloud VM — and they keep changing. Letting Claude Code or Codex work directly on each one means installing it, logging in, and copying API keys, Git credentials, MCP servers, skills and preferences again, every time. Some servers have no outbound internet, so the agent cannot run there at all. And on a shared machine your credentials sit where other users and admins can reach them.

**Containers restrict ports, so port-forwarding setups fail.** Many dev environments run inside containers that cannot open or forward extra ports, which rules out remote-agent setups built on port forwarding. SSH, on the other hand, is the one thing practically every server provides: if you can log in, it is there.

## The solution

The agent stays on your laptop with all its setup; the server is only an execution target; the two talk over a single SSH connection — no port forwarding, no extra open ports.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/architecture-dark.svg">
  <img alt="Laptop (agent, credentials, Git, rdev) connected to the server over one SSH connection carrying file routing (mutagen) and command routing (herdr)" src="docs/assets/architecture.svg">
</picture>

At its core this is **routing on two levels**:

- **File routing.** [mutagen](https://mutagen.io) syncs only the lightweight code between your laptop and the server. Datasets, model weights, checkpoints and experiment outputs stay on the server and are never mapped to your laptop, so local disk usage stays small.
- **Command routing.** The agent edits code locally and sends server commands through `rdev`, which runs them in a persistent [herdr](https://herdr.dev) pane on the server. Long jobs are not bound by the agent's tool timeouts and keep running through network drops or a closed lid, and you can open the pane at any time to watch what is actually happening.

| component | role |
|---|---|
| mutagen | two-way-safe file sync over SSH; server-only paths are excluded |
| herdr | persistent pane on the server, reached over SSH |
| `rdev` | the single entry point for server commands: flush the sync, run in the pane, stream back output and the remote exit code |
| `remote-dev-init` | set up a project, or migrate an existing server-side Git checkout to your laptop |
| hooks + skill | keep Claude Code / Codex on this workflow: inject sync status, warn about conflicts, block direct `ssh` to the dev host |

Git stays on your laptop; the server has no `.git` and no credentials.

## Quick start

**Requirements:** macOS (tested) or Linux (untested) with `bash`, `jq`, `perl` and OpenSSH; a host alias in `~/.ssh/config`; [mutagen](https://mutagen.io/documentation/introduction/installation) and [herdr](https://herdr.dev) on the laptop. The server needs SSH and `bash`.

**1. Install**

```bash
git clone https://github.com/changingxsy/agent-over-ssh.git ~/src/agent-over-ssh
~/src/agent-over-ssh/install.sh
herdr machine add devbox            # once per server
```

`install.sh` symlinks `rdev` and `remote-dev-init` into `~/.local/bin` and the agent skill into `~/.claude/skills` / `~/.codex/skills`. It never overwrites existing files.

**2. Create a project** — preview first, and list what stays server-only:

```bash
remote-dev-init --host devbox --remote /srv/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs --plan
remote-dev-init --host devbox --remote /srv/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs
```

**3. Run on the server**

```bash
cd ~/work/myproj
rdev 'pytest'                        # run and wait; exits with the remote exit code
rdev --bg 'python train.py'          # long job: prints a TOKEN immediately
rdev --wait TOKEN --timeout 540      # collect it, also after a network drop
rdev up                              # check / repair sync, pane, uncollected jobs
```

**4. Wire up your agent** — merge [`examples/claude-settings.hooks.json`](examples/claude-settings.hooks.json) into `~/.claude/settings.json` and/or [`examples/codex-hooks.json`](examples/codex-hooks.json) into `~/.codex/hooks.json`, replacing `/path/to/agent-over-ssh`. From then on, in any project with `.remote-dev.toml`, the agent edits locally and runs server commands with `rdev`.

## Documentation

| | |
|---|---|
| [Architecture](docs/architecture.md) | why SSH only, where credentials and Git live |
| [File routing](docs/file-sync.md) | what is synced, server-only paths, conflicts, migrating a server-side repo, build metadata |
| [Command routing](docs/command-routing.md) | what `rdev` does step by step, long jobs, network loss, exit codes |
| [Agent integration](docs/agent-integration.md) | hooks, skill, main vs. delegated agents, customizing the guard |
| [Reference](docs/reference.md) | all flags of `rdev` and `remote-dev-init`, `.remote-dev.toml` |
| [FAQ](docs/faq.md) | comparisons with VS Code Remote-SSH, agents on the server, sshfs/rsync |

## License

[MIT](LICENSE)
