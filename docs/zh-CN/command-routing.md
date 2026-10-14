# 命令分流

[English](../command-routing.md) · 简体中文 · [文档目录](../../README.zh-CN.md#文档)

Agent 不需要知道命令在**哪里**运行。它只在本地改文件，然后调用 `rdev '<cmd>'`；同步、远程执行和断网恢复都由下面几层处理。

## `rdev` 做了什么

每次 `rdev '<cmd>'`：

1. **找到项目。** 从当前目录向上查找 `.remote-dev.toml`，并把本地子目录映射到服务器上对应的目录。
2. **检查同步。** mutagen 正在连接时等待（`wait_sync`，默认 30 秒），暂停时恢复，然后刷新同步。遇到冲突或同步离线时**拒绝运行**，保证不会在旧代码上执行。
3. **找到 pane。** 在服务器上查找或创建 herdr 工作区 `rdev-<name>`（工作目录为远程项目目录）。每个项目同一时间只运行一个命令，pane 忙时拒绝。
4. **提交运行。** 把命令和版本变量写成一个小脚本，上传到 `~/.rdev/run/<name>/<TOKEN>.sh`，在 pane 中运行；日志和退出码记录在服务器上。
5. **等待并传回输出。** 打印输出（默认最后 300 行），并以远程退出码退出。断网期间会持续重试，最长 `net_wait` 秒（默认 300 秒）；无论如何，任务都会在服务器上继续运行。
6. **再刷新一次同步**，把服务器上生成的文件带回本机。

命令要用单引号括起来，例如 `rdev 'echo $VERSION'`，这样变量才会在服务器上展开。

## 每类命令在哪里运行

| 命令类型 | 例子 | 在哪里运行 | 如何保证 |
|---|---|---|---|
| 读写代码、搜索 | Agent 的文件工具、`rg`、`grep` | 本机 | 文件就在本机，由 mutagen 同步 |
| Git | `git commit`、`git push` | 本机 | 服务器上没有 `.git`；规则中也写明了 |
| 构建、测试、训练等需要服务器环境的命令 | `rdev 'pytest'`、`rdev --bg 'python train.py'` | 服务器 | **规则**：由会话 hook 注入，技能中也有说明 |
| 直接 `ssh` / `scp` / `sftp` 到开发机 | `ssh devbox ...` | 被拦截 | **硬拦截**：`PreToolUse` hook 拒绝并提示改用 `rdev` |
| 委派 Agent 运行 `rdev` / `mutagen` / `herdr` | 由 Claude Code 调用的 Codex | 被拦截 | **硬拦截**：委派 Agent 只负责编辑 |

### 如果 Agent 误把服务器命令在本地运行了怎么办？

这一类目前不拦截，靠规则约束。从第一轮对话开始，Agent 的上下文里就写着“用 `rdev '<cmd>'` 运行服务器命令”以及当前同步状态，技能里也会重复说明。实际中，本机通常没有服务器上的数据、GPU 或工具链，这类命令在本地会失败，Agent 随后就会改用 `rdev`。如果你的本机恰好有相同环境、而结果差异对你很重要，可以自己加一条拦截规则，见 [Agent 集成 → 自定义 hooks](agent-integration.md#自定义-hooks)。

## 长任务

Agent 的工具调用有时间上限（Claude Code 的 Bash 工具最长 10 分钟）。可能超时的任务，先在后台启动，再分段收取：

```bash
rdev --bg 'python train.py'          # 立即返回一个 TOKEN
rdev --wait TOKEN --timeout 540      # 最多等 9 分钟；退出码为 124 时重复执行
rdev --log TOKEN --lines 1000        # 随时查看更多日志
```

普通的 `rdev '<cmd>'` 最多等待 `--timeout` 秒（默认 1800 秒），命令仍在运行时以 124 退出；任务会继续运行，之后用 `--wait` 收取。

**实时查看。** 命令运行在一个真实的终端 pane 中，你随时可以去看：打开服务器的 herdr 会话（例如 `herdr --remote devbox`），切换到 `rdev-<name>` 工作区即可。日志也保存在服务器的 `~/.rdev/run/<name>/<TOKEN>.log` 中。

**一次一个。** 每个项目的 pane 同一时间只运行一个命令；第一个还在运行时，第二个 `rdev` 会被拒绝。`--force` 可以跳过这项检查（确定没问题时再用），`rdev --clear-stale` 可以清除崩溃运行遗留的占用标记。

## 断网与合上笔记本

本机上的 Agent 会话还在，但 SSH 连接会断开。接下来会发生：

- 正在运行的命令**继续**在服务器端的 pane 中运行。
- 正在等待的 `rdev` 会持续重试 `net_wait` 秒，然后带着 token 以 125 退出。
- 本地修改由 mutagen 排队，重连后同步。
- `rdev` 在本地记录了已启动的任务（`~/.cache/rdev/<name>.jobs`），所以 `rdev up` 会列出已完成或仍在运行、但还没收取的任务，提示 hook 也会告诉 Agent。

恢复方法始终一样：先 `rdev up`，再 `rdev --wait TOKEN`，**不要**重新运行命令。

## 退出码

| 退出码 | 含义 | 怎么处理 |
|---|---|---|
| 远程退出码 | 命令已结束 | 正常处理 |
| 2 | 配置或 herdr 问题 | 看提示信息；如果提示 `herdr machine add` / `reconnect`，在你自己的终端里运行 |
| 3 | 同步离线或停止 | 继续在本地编辑，稍后重试 `rdev up` |
| 4 | 同步冲突 | 运行 `mutagen sync list <session>`，决定保留哪一边 |
| 124 | 超过 `--timeout` 仍在运行 | `rdev --wait TOKEN` |
| 125 | 运行中服务器不可达 | 任务仍在运行；`rdev up && rdev --wait TOKEN` |
