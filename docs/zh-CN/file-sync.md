# 文件分流

[English](../file-sync.md) · 简体中文 · [文档目录](../../README.zh-CN.md#文档)

mutagen 让本机和服务器上的项目目录保持同步，但只同步轻量的部分。重型文件留在服务器上，本机只保留 Agent 需要阅读和编辑的内容。

## 什么放在哪里

| 同步（两边都有） | 只留在服务器 | 只在本机 |
|---|---|---|
| 源代码、配置、脚本、文档、小型测试数据 | 数据集、模型权重、checkpoint、实验产物、日志、虚拟环境、编译产物 | `.git`、Agent 配置与凭据、`.remote-dev.toml`、`.remote-dev.ignores` |

只留在服务器和只在本机的路径只是**不参与同步**，两边都不会被删除。

## 选择只留在服务器的路径

在创建项目时决定：

```bash
remote-dev-init --host gpu1 --remote /data/me/myproj --stack python \
  --ignore /data --ignore /checkpoints --ignore /outputs --ignore '*.ckpt' --plan
```

- **始终忽略：** `.DS_Store`、`/.claude`、`/.codex`、`/.remote-dev.toml`、`/.remote-dev.ignores`、`.env`、`.git.migrated-*`。（`.env` 被忽略，所以两边各自保留自己的一份。）
- **`--stack`** 按技术栈追加常见产物（逗号分隔）：
  - `go`：`/bin /dist`
  - `node`：`node_modules /dist /build /.next /coverage`
  - `python`：`__pycache__ .venv venv *.pyc .pytest_cache .mypy_cache`
- **`--ignore PATTERN`**（可重复）追加项目自己的大文件路径，使用 [mutagen 忽略语法](https://mutagen.io/documentation/synchronization/ignores)：`/data` 表示项目根目录下的 `data`；`*.ckpt` 匹配任意位置。
- 迁移服务器上的 Git 仓库时，原仓库 `.gitignore` 忽略的所有文件都会自动变成只留在服务器。

`--ignore` 的路径和迁移得到的忽略项记录在 `.remote-dev.ignores` 中。全新仓库的初始 `.gitignore` 也由整个列表生成（`.remote-dev*` 文件除外）。

> 对于已有的服务器目录，先看一下顶层目录的大小（在服务器上运行 `du -sh *`），决定哪些目录永远不该同步到本机。之后再修改列表需要重建同步会话。

### 之后修改列表

```bash
mutagen sync terminate myproj
mutagen sync create --name myproj --mode two-way-safe --ignore-vcs \
  --ignore .DS_Store --ignore /.claude --ignore /.codex --ignore /.remote-dev.toml \
  --ignore /.remote-dev.ignores --ignore .env --ignore '.git.migrated-*' \
  --ignore <技术栈和项目路径...> \
  ~/work/myproj devbox:/srv/myproj
```

然后同步更新 `.remote-dev.ignores`，这样以后重跑 `remote-dev-init` 时使用的是同一份列表。终止会话不会删除任何文件。

## 同步的行为

- **`two-way-safe` 模式。** 修改双向同步；如果两边改了同一个文件，mutagen 会记录冲突，而不是自动选一边。存在冲突时 `rdev` 拒绝运行（退出码 4）；用 `mutagen sync list myproj` 查看，再决定保留哪一边。
- **忽略版本控制目录**（`--ignore-vcs`），所以 `.git` 永远不会到服务器上。
- **服务器生成的文件会同步回来。** 每次运行结束后 `rdev` 会再刷新一次，服务器上的格式化、代码生成、lockfile 更新都会出现在本地工作区，用 `git status` 检查即可。
- **离线修改会排队。** 断网时可以继续编辑，重连后 mutagen 会补上；`rdev` 也会等同步完成再运行。

## 创建或迁移项目

`remote-dev-init` 会探测两边的状态并选择模式：

| 模式 | 适用情况 | 做什么 |
|---|---|---|
| `new` | 远程目录不存在或为空 | 在服务器上 `mkdir -p`，本地 `git init` 并创建初始提交，写入 `.remote-dev.toml`，创建 mutagen 会话 |
| `migrate` | 远程目录有 `.git`（需要 `--migrate-server-git`） | 检查服务器仓库干净、没有 stash、所有分支都已推送；用 rsync 把 `.git` 复制到本机并检出；把服务器上被忽略的文件记为只留服务器；把服务器的 `.git` 重命名为 `.git.migrated-<日期>`；创建会话 |
| `resume` | 之前的运行被中断 | 完成剩余步骤 |

当远程目录有文件但没有 Git，或本地目录非空且没有 Git 时，它会拒绝执行（退出码 10），而不是猜测。每一步都会先检查是否已经完成，所以重跑是安全的。要撤销迁移，在服务器上执行 `mv .git.migrated-<日期> .git`。

`--plan` 只打印模式和计划动作，不做任何修改。如果 herdr machine 还没保存，它会以退出码 20 结束，提示你在自己的终端里运行 `herdr machine add <host>`（需要交互式 SSH 认证），然后重跑。

## 服务器没有 Git 时的构建元数据

每次 `rdev` 运行都会从本地仓库导出这些变量：

| 变量 | 值 |
|---|---|
| `VERSION` | `git describe --tags --always --dirty`，或 `dev` |
| `COMMIT` | 短哈希，工作区有改动时带 `-dirty` |
| `COMMIT_FULL` | 完整哈希 |
| `BUILD_DATE` | UTC 时间，ISO 8601 格式 |
| `SOURCE_DIRTY` | `true` / `false` |

同时写入两个会被同步的文件，供不是由 `rdev` 启动的构建使用：

- `.build-meta.json`：`{"version", "commit", "commit_full", "dirty"}`
- `.build-meta.files`：以 NUL 分隔的文件列表，包括已跟踪文件和未被忽略的未跟踪文件（`git ls-files --cached --others --exclude-standard -z`）

两者都通过 `.git/info/exclude` 排除在 Git 之外。项目脚本可以这样约定：

- Shell：`VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"`
- Go：`go build -buildvcs=false -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE"`
- 直接调用 `git` 的脚本，在没有 `.git` 时应回退到 `.build-meta.*`。迁移之后，用 grep 搜索脚本里的 `git `：这类失败可能是静默的（例如 `git ls-files | xargs gofmt` 什么也不会格式化）。
