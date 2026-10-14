# 架构

[English](../architecture.md) · 简体中文 · [文档目录](../../README.zh-CN.md#文档)

agent-over-ssh 把开发拆到两台机器上，两者之间只有一条 SSH 连接：你和 Agent 在本机**思考和编辑**，代码在服务器上**运行**。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/architecture.zh-CN-dark.svg">
  <img alt="架构：本机与服务器之间只有一条 SSH 连接，承载文件分流和命令分流" src="../assets/architecture.zh-CN.svg">
</picture>

## 为什么只用 SSH

两个通道都建立在 SSH 之上，不另开连接：

- **mutagen** 通过 SSH 在服务器上启动一个小的 agent 程序，借这条会话的标准输入输出同步文件。
- **herdr** 同样通过 SSH 连到服务器端进程；`rdev` 通过 herdr CLI 操作 pane，通过普通的 `ssh` 读取运行目录。

所以不需要监听新端口、不做端口转发，也不需要反向隧道。正因如此，它能用在只暴露 `sshd` 的容器里、只放行 22 端口的防火墙后面，以及不能访问外网的机器上：辅助程序是从本机通过 SSH 部署过去的（由 mutagen 自己和 `herdr machine add` 完成），不需要服务器自己下载。

## 什么放在哪里

| | 本机 | 服务器 |
|---|---|---|
| Agent（Claude Code / Codex）及其登录状态、MCP、技能 | ✓ | |
| API key、Git / GitHub token | ✓ | |
| Git 仓库（`.git`） | ✓ | |
| 项目代码 | ✓ | ✓（同步的副本） |
| 数据集、模型权重、checkpoint、实验产物 | | ✓（只留在服务器） |
| `.remote-dev.toml`、`.remote-dev.ignores` | ✓（不纳入 Git） | |
| 运行脚本、日志、退出码（`~/.rdev/run/<name>/`） | | ✓ |
| 任务记录、pane 缓存（`~/.cache/rdev/`） | ✓ | |
| herdr 工作区 `rdev-<name>` | | ✓ |
| mutagen / herdr 辅助程序 | ✓ | ✓（不含凭据） |

在共享服务器上，其他用户和管理员能看到你的代码和产物（和任何远程工作一样），但永远看不到你的密钥和 token。

## 为什么 Git 只放在本机

- **唯一的事实来源。** 服务器上没有 `.git`，两边不可能分叉，Git 也不可能在服务器上被误执行。
- **凭据不出本机。** 推送需要 token，Git 留在本地，token 就不用离开本机。
- **版本信息照样能到服务器。** 每次 `rdev` 运行都会从本地仓库注入 `VERSION`、`COMMIT` 等变量；不是通过 `rdev` 启动的构建，可以读取同步过去的 `.build-meta.json`。见[文件分流 → 构建元数据](file-sync.md#服务器没有-git-时的构建元数据)。

## 设计原则

- **绝不在旧代码上运行。** 每次运行前，`rdev` 都会等待同步连上并刷新；同步离线或有冲突时拒绝运行。
- **绝不丢失正在运行的任务。** 命令在服务器端的 pane 中运行，日志和退出码记录在服务器上，本机断网不会杀掉它。
- **绝不盲目重跑。** 每次运行都有一个 token；断网后用 `rdev --wait TOKEN` 收取同一次运行的结果，hooks 也会提醒 Agent 有未收取的任务。
- **所有外部调用都有超时。** ssh、mutagen、herdr 的调用都有时间上限（用一个 perl `alarm` 小包装实现，因为 macOS 没有 `timeout(1)`），不会无限挂起。
- **初始化可重入、可回退。** `remote-dev-init` 中断后可以直接重跑，`--plan` 只读不改；迁移服务器仓库时只重命名 `.git`，不删除。
- **引导 Agent，而不是盲目信任。** hooks 注入规则和实时状态，并硬性拦截最关键的两类错误（见 [Agent 集成](agent-integration.md)）。
