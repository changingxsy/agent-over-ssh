# 参考

[English](../reference.md) · 简体中文 · [文档目录](../../README.zh-CN.md#文档)

## `rdev`

```
rdev [--timeout SEC] [--lines N] [--force] '<command>'   运行并等待；以远程退出码退出
rdev --bg [--force] '<command>'                          启动后不等待；打印 token
rdev --wait TOKEN [--timeout SEC] [--lines N]            等待 / 收取一次运行
rdev --log TOKEN [--lines N]                             打印一次运行的日志
rdev up [--quiet]                                        检查并修复同步、herdr、pane；列出未收取的任务
rdev --clear-stale                                       清除崩溃运行遗留的占用标记
```

| 选项 | 默认值 | 含义 |
|---|---|---|
| `--timeout SEC` | 1800 | 等待多久后以 124 退出（任务继续运行） |
| `--lines N` | 300 | 打印日志的最后多少行 |
| `--force` | 关 | pane 忙时也运行 |
| `--quiet` | 关 | 用于 `up`：只输出一行状态，不显示 mutagen 详情 |
| `--status` | | `up` 的别名 |

每次运行都会导出这些变量：`VERSION`、`COMMIT`、`COMMIT_FULL`、`BUILD_DATE`、`SOURCE_DIRTY`（见[文件分流](file-sync.md#服务器没有-git-时的构建元数据)）。

退出码：远程命令的退出码，或 2 / 3 / 4 / 124 / 125（见[命令分流](command-routing.md#退出码)）。

## `remote-dev-init`

```
remote-dev-init --host H --remote /abs/path [--dir ~/work/NAME] [--name NAME]
                [--stack go,node,python] [--machine LABEL] [--ignore PATTERN]...
                [--migrate-server-git] [--plan]
```

| 选项 | 默认值 | 含义 |
|---|---|---|
| `--host` | 必填 | `~/.ssh/config` 中的 SSH 别名 |
| `--remote` | 必填 | 服务器上的项目绝对路径（不能是顶层路径） |
| `--dir` | `~/work/<远程目录名>` | 本地项目目录 |
| `--name` | 远程目录名 | 项目名（转为小写）；也是 mutagen 会话名和 herdr 工作区 `rdev-<name>` 的名字 |
| `--stack` | 无 | 按技术栈追加忽略项：`go`、`node`、`python` |
| `--machine` | 与 `--host` 相同 | herdr machine 标签 |
| `--ignore` | 无 | 只留在服务器的路径，mutagen 忽略语法；可重复 |
| `--migrate-server-git` | 关 | 远程目录是 Git 仓库：把 Git 迁移到本机 |
| `--plan` | 关 | 只读：探测两边状态并打印将要执行的操作 |

| 退出码 | 含义 |
|---|---|
| 0 | 完成 |
| 2 | 用法错误或某一步失败（提示信息会说明） |
| 10 | 需要你做决定或加参数（例如 `--migrate-server-git`、非空目录没有 Git） |
| 20 | herdr machine 未保存：运行 `herdr machine add <host>` 后重跑 |

迁移还需要两边都有 `rsync`。

## `.remote-dev.toml`

放在项目根目录，只在本地；由 `remote-dev-init` 生成并排除在 Git 之外。[示例](../../examples/remote-dev.toml.example)：

```toml
host        = "devbox"          # ~/.ssh/config 中的 SSH 别名
machine     = "devbox"          # herdr machine 标签（herdr machine add devbox）
remote_path = "/srv/myproj"     # 服务器上的项目绝对路径
mutagen     = "myproj"          # mutagen 同步会话名
name        = "myproj"          # 可选；herdr 工作区名为 rdev-myproj
# wait_sync = 30                # 可选：等待同步连上的秒数
# net_wait  = 300               # 可选：等待期间容忍断网的秒数
```

## 文件与状态

| 路径 | 位置 | 内容 |
|---|---|---|
| `.remote-dev.toml`、`.remote-dev.ignores` | 本机，项目根目录 | 配置和只留服务器的路径（不纳入 Git） |
| `.build-meta.json`、`.build-meta.files` | 两边（同步） | 供非 `rdev` 启动的构建使用的版本信息 |
| `~/.cache/rdev/<name>.pane` | 本机 | 缓存的 herdr pane id |
| `~/.cache/rdev/<name>.jobs` | 本机 | 已启动的运行及其状态（最近 50 条） |
| `~/.rdev/run/<name>/<TOKEN>.{sh,log,rc,running}` | 服务器 | 运行脚本、输出、退出码、占用标记 |
| `.git.migrated-<日期>` | 服务器，项目根目录 | 迁移后服务器原来的 `.git` |

## 移除项目配置

```bash
mutagen sync terminate myproj
herdr --machine devbox workspace list          # 找到 rdev-myproj 的 id
herdr --machine devbox workspace close <id>
rm ~/.cache/rdev/myproj.*
```

本地和远程的项目目录不会被动；如果不再需要，请自行删除。
