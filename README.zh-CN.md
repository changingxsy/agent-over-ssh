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

## 封装了什么：命令分流

tether 的核心是把“在哪里执行”这件事封装起来：Agent 只管在本地改代码和调用 `rdev`，同步、远程执行、断网恢复都由下面几层处理。

### 1. `rdev`：远程执行的唯一入口

`rdev '<cmd>'` 每次运行都会依次：

1. 从当前目录向上查找 `.remote-dev.toml`，把本地子目录映射到服务器上对应的子目录。
2. 检查 mutagen 同步：未连接时等待（默认 30 秒），暂停时自动恢复，然后 flush；有冲突或同步离线就**拒绝运行**，保证不会在旧代码上执行。
3. 找到或创建服务器上的 herdr workspace `rdev-<name>`。同一项目同时只允许一个命令，忙时拒绝。
4. 注入本地 Git 的版本信息（`VERSION`、`COMMIT` 等），在 pane 中执行，输出写入服务器上的日志和退出码文件。
5. 等待结束并取回输出；断网时最多等 `net_wait` 秒，任务在服务器上继续运行，凭 TOKEN 之后收取。
6. 结束后再 flush 一次，把服务器上生成的文件（格式化结果、代码生成、lockfile）同步回本地。

### 2. 命令在哪里执行

| 命令类别 | 例子 | 在哪执行 | 靠什么保证 |
|---|---|---|---|
| 读写代码、搜索 | Agent 的文件工具、`rg`、`grep` | 本地 | 本来就在本地；mutagen 自动同步到服务器 |
| Git | `git commit`、`git push` | 本地 | 服务器没有 `.git`，在那边跑不了 Git；规则里也写明 Git 只在本地 |
| 构建、测试、训练等需要服务器环境的命令 | `rdev 'pytest'`、`rdev --bg 'python train.py'` | 服务器 | **规则提示**：会话开始时 hook 注入规则，skill 里也写明（见下文） |
| 直接 `ssh`/`scp`/`sftp` 到开发机 | `ssh devbox ...` | 禁止 | **硬性拦截**：PreToolUse hook 拒绝，并提示改用 `rdev` |
| 被委派的 Agent 运行 `rdev`/`mutagen`/`herdr` | Claude Code 调用的 Codex | 禁止 | **硬性拦截**：委派的 Agent 只改代码，验证由主 Agent 用 `rdev` 完成 |

hooks 只在含有 `.remote-dev.toml` 的项目里生效，其他目录完全不受影响。

| hook | 作用 |
|---|---|
| `SessionStart` | 运行 `rdev up --quiet`，把同步/herdr 状态和上述规则注入 Agent 上下文；委派的 Agent 收到的是“只改代码”的规则 |
| `UserPromptSubmit` | 每轮对话前只做本地检查（不连服务器）；只在同步断开、有冲突或有未收取任务时提示 |
| `PreToolUse` | 上表中的两项硬性拦截 |

### 3. AI 无意中在本地运行了服务器命令会怎样

目前**不会被拦截**，这一类靠规则约束：

- 会话一开始，Agent 的上下文里就有“服务器命令一律用 `rdev '<cmd>'`”的规则和当前同步状态，[`SKILL.md`](skills/remote-dev/SKILL.md) 里也有同样的说明和退出码处理方法。
- 本地通常没有服务器上的数据、GPU 或工具链（它们本来就是只留在服务器的），这类命令在本地往往会直接失败，Agent 会根据规则改用 `rdev`。
- 但如果本地恰好有相同环境，命令就会在本地执行，结果可能和服务器上不一致。对这类命令有更严格要求时，可以按下一节自己加拦截规则。

## 自定义规则：hook 就是你本机上的代码

所有 hook 都是本机上的 bash 脚本（[`hooks/rdev-hook.sh`](hooks/rdev-hook.sh)），由你自己的 `~/.claude/settings.json` / `~/.codex/hooks.json` 引用，没有任何远程配置。如果某条规则和你要跑的命令冲突，或者你想加更严格的限制，直接改它即可：

- **放宽**：调整 `guard` 分支里的匹配规则，或者从 settings 中删掉对应的 hook。
- **收紧**：在 `guard` 分支里加自己的拒绝规则，例如禁止在本地运行 `python train.py`、`torchrun`，返回 `permissionDecision: "deny"` 并提示改用 `rdev`。
- **验证**：把新例子加到 [`tests/guard-cases.txt`](tests/guard-cases.txt)（`#EXPECT-DENY` 之前的应放行，之后的应拒绝），运行 `tests/run-guard-tests.sh`。
- 改动在下一次工具调用或下一个会话生效，不用重启。建议 fork 后在自己的分支上修改，方便以后合并上游更新。

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

## 测试

```bash
tests/run-guard-tests.sh
```

## 许可证

[MIT](LICENSE)
