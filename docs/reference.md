# Reference

English · [简体中文](zh-CN/reference.md) · [Docs index](../README.md#documentation)

## `rdev`

```
rdev [--timeout SEC] [--lines N] [--force] '<command>'   run and wait; exit with the remote code
rdev --bg [--force] '<command>'                          start without waiting; print the token
rdev --wait TOKEN [--timeout SEC] [--lines N]            wait for / collect a run
rdev --log TOKEN [--lines N]                             print the log of a run
rdev up [--quiet]                                        check & repair sync, herdr, pane; report uncollected jobs
rdev --clear-stale                                       drop busy markers of crashed runs
```

| option | default | meaning |
|---|---|---|
| `--timeout SEC` | 1800 | how long to wait before exiting 124 (the job keeps running) |
| `--lines N` | 300 | how many trailing log lines to print |
| `--force` | off | run even if the pane is busy |
| `--quiet` | off | `up`: one status line, without the mutagen details |
| `--status` | | alias of `up` |

Variables exported to every run: `VERSION`, `COMMIT`, `COMMIT_FULL`, `BUILD_DATE`, `SOURCE_DIRTY` (see [File routing](file-sync.md#build-metadata-without-git-on-the-server)).

Exit codes: the remote command's code, or 2 / 3 / 4 / 124 / 125 (see [Command routing](command-routing.md#exit-codes)).

## `remote-dev-init`

```
remote-dev-init --host H --remote /abs/path [--dir ~/work/NAME] [--name NAME]
                [--stack go,node,python] [--machine LABEL] [--ignore PATTERN]...
                [--migrate-server-git] [--plan]
```

| option | default | meaning |
|---|---|---|
| `--host` | required | SSH alias from `~/.ssh/config` |
| `--remote` | required | absolute project dir on the server (not a top-level path) |
| `--dir` | `~/work/<basename of remote>` | local project dir |
| `--name` | basename of remote | project name (lowercased); mutagen session and herdr workspace `rdev-<name>` |
| `--stack` | none | extra ignores per stack: `go`, `node`, `python` |
| `--machine` | same as `--host` | herdr machine label |
| `--ignore` | none | server-only path, mutagen ignore syntax; repeatable |
| `--migrate-server-git` | off | the remote dir is a Git checkout: move Git to the laptop |
| `--plan` | off | read-only: probe both sides and print what would be done |

| exit | meaning |
|---|---|
| 0 | done |
| 2 | usage error or a failed step (message says which) |
| 10 | needs a decision or flag (e.g. `--migrate-server-git`, non-empty dir without Git) |
| 20 | herdr machine not saved: run `herdr machine add <host>`, then re-run |

Migration additionally needs `rsync` on both sides.

## `.remote-dev.toml`

Lives in the project root, local only; `remote-dev-init` writes it and excludes it from Git. [Example](../examples/remote-dev.toml.example):

```toml
host        = "devbox"          # SSH alias from ~/.ssh/config
machine     = "devbox"          # herdr machine label (herdr machine add devbox)
remote_path = "/srv/myproj"     # absolute project dir on the server
mutagen     = "myproj"          # mutagen sync session name
name        = "myproj"          # optional; herdr workspace becomes rdev-myproj
# wait_sync = 30                # optional: seconds to wait for the sync to connect
# net_wait  = 300               # optional: seconds to ride out a network loss while waiting
```

## Files and state

| path | side | content |
|---|---|---|
| `.remote-dev.toml`, `.remote-dev.ignores` | laptop, project root | config and server-only paths (excluded from Git) |
| `.build-meta.json`, `.build-meta.files` | both (synced) | version metadata for builds not started by `rdev` |
| `~/.cache/rdev/<name>.pane` | laptop | cached herdr pane id |
| `~/.cache/rdev/<name>.jobs` | laptop | started runs and their state (last 50) |
| `~/.rdev/run/<name>/<TOKEN>.{sh,log,rc,running}` | server | run script, output, exit code, busy marker |
| `.git.migrated-<date>` | server, project root | the server's `.git` after a migration |

## Removing a project setup

```bash
mutagen sync terminate myproj
herdr --machine devbox workspace list          # find the id of rdev-myproj
herdr --machine devbox workspace close <id>
rm ~/.cache/rdev/myproj.*
```

Local and remote project directories are left alone; delete them yourself if you no longer need them.
