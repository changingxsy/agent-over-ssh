# tether

**本地编辑，远程运行。** 一套小工具：代码放在笔记本上（Git 也在本地），构建和运行在 SSH 服务器上；人和编码 Agent（Claude Code、Codex）都按同一套流程工作。

[English](README.md)

```
 本地                                           服务器
┌───────────────────────────┐   mutagen    ┌──────────────────────────┐
│ ~/work/myproj  (Git 在此)  │ ◀──────────▶ │ /srv/myproj  (无 .git)    │
│                           │  two-way-safe│                          │
│ rdev 'go test ./...' ─────┼──── herdr ──▶│ herdr workspace          │
│   ◀── 输出 + 退出码 ────────┼──────────────│   rdev-myproj (pane)     │
└───────────────────────────┘              └──────────────────────────┘
```

- **[mutagen](https://mutagen.io)**：本地目录与服务器目录双向同步。
- **[herdr](https://herdr.dev)**：服务器上的常驻 pane，合盖、换网络后任务继续跑。
- **Git 只在本地**：服务器没有 `.git`，版本信息在每次运行时注入。
- **`rdev`**：检查并 flush 同步 → 在 pane 中执行 → 取回输出和远程退出码。

## 为什么

Agent 和编辑器擅长处理本地文件，但工具链、数据或 GPU 在服务器上。直接 `ssh` 执行一换网就断；两边都有 Git 又容易分叉。tether 把服务器变成纯执行端：

- `rdev` 不会在旧代码上运行：先等同步连上并 flush。
- 断网时正在跑的命令**继续在服务器上运行**，之后用 `rdev --wait TOKEN` 收结果，而不是重跑。
- Claude Code / Codex 的 hooks 会在会话开始注入同步状态，提示冲突或未收取的任务，并拦截直接 `ssh`/`scp` 到开发机。

## 依赖

- macOS（已验证）或 Linux（未验证），`bash`、`jq`、`perl`，`~/.ssh/config` 中配置好的主机别名
- 本地安装 [mutagen](https://mutagen.io/documentation/introduction/installation)
- 本地安装 [herdr](https://herdr.dev)，并执行过 `herdr machine add <host>`

## 安装

```bash
git clone https://github.com/changingxsy/tether.git ~/src/tether
~/src/tether/install.sh
```

`install.sh` 把 `rdev`、`remote-dev-init` 软链接到 `~/.local/bin`（可用 `BIN_DIR` 覆盖），把 skill 链接到 `~/.claude/skills` / `~/.codex/skills`，不会覆盖已有文件。Hooks 需手动启用：把 [`examples/claude-settings.hooks.json`](examples/claude-settings.hooks.json) 合并进 `~/.claude/settings.json`，或把 [`examples/codex-hooks.json`](examples/codex-hooks.json) 合并进 `~/.codex/hooks.json`，并替换 `/path/to/tether`。

## 快速上手

```bash
# 先预览（只读），再创建：本地仓库 + 远程目录 + mutagen 会话
remote-dev-init --host devbox --remote /srv/myproj --stack go --plan
remote-dev-init --host devbox --remote /srv/myproj --stack go

cd ~/work/myproj
rdev 'go test ./...'                  # 运行并等待，退出码即远程退出码
rdev --bg './scripts/run-server.sh'   # 长任务：立即返回 TOKEN
rdev --wait TOKEN --timeout 540       # 收取结果（可重复）
rdev up                               # 检查/修复同步、herdr pane，列出未收取任务
```

`remote-dev-init --migrate-server-git` 可把服务器上已有的 Git 仓库迁到本地（先检查服务器仓库干净且已推送，服务器 `.git` 只重命名不删除）。详见 [`skills/remote-dev/references/setup.md`](skills/remote-dev/references/setup.md)。

项目配置在 `.remote-dev.toml`（[示例](examples/remote-dev.toml.example)），已自动排除出 Git。

## 退出码

| 退出码 | 含义 |
|---|---|
| 远程退出码 | 命令执行完毕 |
| 2 | 配置或 herdr 问题（提示信息会说明要执行什么） |
| 3 | 同步离线或停止：继续本地编辑，稍后重试 |
| 4 | 同步冲突：用 `mutagen sync list <session>` 处理 |
| 124 | 超过 `--timeout` 仍在运行：`rdev --wait TOKEN` |
| 125 | 运行中服务器不可达：任务仍在跑，恢复后 `rdev up && rdev --wait TOKEN` |

## 服务器无 Git 时的版本信息

每次 `rdev` 运行都会导出 `VERSION`（`git describe --tags --always --dirty`）、`COMMIT`、`COMMIT_FULL`、`BUILD_DATE`、`SOURCE_DIRTY`，并在同步目录写入 `.build-meta.json` / `.build-meta.files`，供不经 `rdev` 启动的构建使用。

## 配合编码 Agent

[`skills/remote-dev/SKILL.md`](skills/remote-dev/SKILL.md) 是 Claude Code / Codex 格式的 skill，描述工作流程和退出码处理。启用 hooks 后：

| hook | 作用 |
|---|---|
| `SessionStart` | 运行 `rdev up --quiet`，注入状态和规则 |
| `UserPromptSubmit` | 仅本地检查；只在断连、冲突或有未收取任务时提示 |
| `PreToolUse` | 拦截到开发机的 `ssh`/`scp`/`sftp`；由 Claude Code 委派的 Codex 不得运行 `rdev`/`mutagen`/`herdr` |

## 测试

```bash
tests/run-guard-tests.sh
```

## 许可证

[MIT](LICENSE)
