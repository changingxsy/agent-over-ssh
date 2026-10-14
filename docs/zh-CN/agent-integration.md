# Agent 集成

[English](../agent-integration.md) · 简体中文 · [文档目录](../../README.zh-CN.md#文档)

`rdev` 是一个普通的命令行工具，任何 Agent 或人都可以用。针对 Claude Code 和 Codex，项目还提供了一个技能和一组 hooks，让 Agent 不用提醒也会遵循这套流程。

两者都只在包含 `.remote-dev.toml` 的项目中生效，其他目录完全不受影响。

## 技能

`install.sh` 会把 [`skills/remote-dev`](../../skills/remote-dev/SKILL.md) 链接到 `~/.claude/skills`，以及（如果存在）`~/.codex/skills`。它告诉 Agent：

- 在本地编辑；所有服务器端命令都用 `rdev '<cmd>'` 运行；Git 只在本地；
- 可能超出单次工具调用时长的任务，用 `--bg` / `--wait`；
- 每个退出码的含义和处理方法（退出码 125 之后绝不重跑任务）；
- 如何用 `remote-dev-init` 创建或迁移项目（[`references/setup.md`](../../skills/remote-dev/references/setup.md)）。

## Hooks

Hooks 需要手动启用。把 [`examples/claude-settings.hooks.json`](../../examples/claude-settings.hooks.json) 合并进 `~/.claude/settings.json`，和/或把 [`examples/codex-hooks.json`](../../examples/codex-hooks.json) 合并进 `~/.codex/hooks.json`，并替换其中的 `/path/to/agent-over-ssh`。

| hook | 作用 |
|---|---|
| `SessionStart` | 运行 `rdev up --quiet`，把真实的同步 / herdr 状态和工作流规则注入 Agent 的上下文 |
| `UserPromptSubmit` | 每轮对话前做一次只在本地进行的检查（不连服务器）；只在同步断开、有冲突或有未收取任务时提示 |
| `PreToolUse` | 硬拦截直接 `ssh` / `scp` / `sftp` 到开发机，以及委派 Agent 运行 `rdev` / `mutagen` / `herdr` |

## 主 Agent 与委派 Agent

**主 Agent**（你正在对话的 Claude Code 或 Codex）负责运行 `rdev` 和管理 Git。

**委派 Agent**（Claude Code 通过 Codex 插件启动的 Codex，可通过环境变量 `CLAUDECODE` 或 `CODEX_COMPANION_SESSION_ID` 识别）只在本地编辑代码。它的会话 hook 注入的是“只编辑”规则，`PreToolUse` hook 会拒绝 `rdev`、`mutagen` 和 `herdr`。主 Agent 用 `rdev` 验证结果并把错误反馈回去。这样 pane、同步和 Git 都只有一个负责人。

## 自定义 hooks

每个 hook 都是你本机上的一个普通 bash 脚本（[`hooks/rdev-hook.sh`](../../hooks/rdev-hook.sh)），在你自己的配置文件中引用，不涉及任何远程配置。如果某条规则妨碍了你，或者你想加更严格的限制，直接修改它：

- **放宽：** 调整 `guard` 分支中的匹配规则，或者从配置中去掉某个 hook。
- **收紧：** 在 `guard` 分支中添加自己的拒绝规则，例如拦截本地运行 `python train.py` 或 `torchrun`，返回 `permissionDecision: "deny"` 并提示改用 `rdev`。
- **测试：** 在 [`tests/guard-cases.txt`](../../tests/guard-cases.txt) 中添加示例（`#EXPECT-DENY` 之前的行必须放行，之后的行必须拒绝），然后运行 `tests/run-guard-tests.sh`。

修改在下一次工具调用或下一个会话生效。把你的改动放在自己 fork 的一个分支上，之后合并上游更新会比较方便。
