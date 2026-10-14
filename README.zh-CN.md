# tether

**只靠 SSH，把本地的 AI Agent 接到任意服务器上。** Agent、凭据和 Git 都留在你的电脑上；服务器只负责运行代码，连接只走一个 SSH 端口。

[English](README.md)

```
本地：Claude Code / Codex · API key · Git token · MCP · ~/work/myproj（Git 在此）
  │
  │  SSH（只用这一个端口，不做端口转发）
  │   ├─ mutagen：同步代码；数据、模型留在服务器
  │   └─ herdr  ：rdev 'python train.py' 在常驻 pane 中运行，断网后继续，输出和退出码传回本地
  ▼
服务器：/srv/myproj（无 .git、无凭据，只运行代码）
```

## 为什么要做 tether

科研和开发中常常要同时用好几台服务器：实验室 GPU 机、学校集群、云主机……如果让 AI Agent 直接在每台服务器上工作，就得在每台机器上重新安装、登录、配置一遍 Claude Code / Codex、API key、Git 凭据、MCP、skills 和各种偏好。这些东西本地早就配好了，在远程重复一遍既繁琐，又要把凭据放到别人管理的机器上。

tether 反过来：**Agent 留在本地，服务器只当执行端，两者之间只用 SSH 连接。**

- **凭据永远不出本机。** API key、Agent 登录状态、Git/GitHub token、MCP 配置都只存在本地。服务器上只有项目代码，以及 mutagen、herdr 通过 SSH 自动部署的两个辅助程序（都不含任何凭据）。在共享服务器上，也不用担心其他用户或管理员接触到你的密钥。
- **只要能 ssh 就能用，普适性强。** 很多服务器出于安全策略禁止端口转发、不开放额外端口，甚至不能访问外网，需要通过转发端口让 Agent 连接的方案在这些机器上就用不了。tether 的同步（mutagen）和远程执行（herdr）都是用 SSH 在服务器上启动辅助程序、通过标准输入输出通信，**不需要端口转发，也不需要额外开端口**。SSH 是登录服务器的前提，所以凡是你能登录的服务器都能用。
- **一处配置，多台复用。** 新增一台服务器只需要 `~/.ssh/config` 里的一个别名，加上一次 `remote-dev-init`；本地的 Agent 配置原样复用。
- **SSH 之上的完整协同。** 代码同步、远程执行、断网续跑、版本信息注入、Agent 规则约束全部建立在这一条 SSH 连接上：
  - `rdev` 不会在旧代码上运行：先等同步连上并 flush。
  - 断网或合盖时正在跑的命令**继续在服务器上运行**，之后用 `rdev --wait TOKEN` 收结果，而不是重跑。
  - Git 只在本地，服务器没有 `.git`，避免两边分叉；版本信息在每次运行时注入。
  - Claude Code / Codex 的 hooks 会在会话开始时注入同步状态，提示冲突或未收取的任务，并拦截直接 `ssh`/`scp` 到开发机。

## 本地放什么，服务器放什么

tether 只把**轻量的代码**同步到本地，大文件留在服务器上不同步。因此初始化时需要你自己判断哪些路径要同步、哪些只留在服务器：

| 同步（两边都有） | 只留在服务器（用 `--ignore` 排除） | 只在本地 |
|---|---|---|
| 源代码、配置、脚本、文档、小型测试数据 | 数据集、模型权重、checkpoint、实验输出、日志、虚拟环境、编译产物 | `.git`、Agent 配置与凭据、`.remote-dev.toml` |

```bash
remote-dev-init --host gpu1 --remote /data/me/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs --ignore '*.ckpt' --plan
```

- `--stack` 自动排除常见产物（如 python 的 `.venv`、`__pycache__`），`--ignore` 用于补充项目自己的大目录，规则语法同 mutagen（`/data` 表示项目根目录下的 `data`）。
- 迁移服务器上已有的 Git 项目时（`--migrate-server-git`），原仓库 `.gitignore` 忽略的文件会自动设为只留在服务器。
- 被排除的路径两边都不会被删除，只是不再同步。初始化后想调整，需要重建 mutagen 会话：`mutagen sync terminate <name>`，再用新的 `--ignore` 列表执行 `mutagen sync create`（参数可参考 `remote-dev-init` 的第 3 步），并更新 `.remote-dev.ignores`。

## 组成

- **[mutagen](https://mutagen.io)**：经 SSH 双向同步本地目录和服务器目录（`two-way-safe`）。
- **[herdr](https://herdr.dev)**：经 SSH 管理服务器上的常驻 pane，合盖、换网络后任务继续跑。
- **`rdev`**：检查并 flush 同步 → 在 pane 中执行 → 取回输出和远程退出码。
- **`remote-dev-init`**：新建或迁移项目。
- **hooks + skill**：让 Claude Code / Codex 按这套流程工作。

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
