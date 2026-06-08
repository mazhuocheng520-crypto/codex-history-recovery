# Codex Desktop Missing Chat History Recovery

修复 Codex Desktop 左侧历史对话、项目对话显示不全的问题。

Fix Codex Desktop missing chat history, hidden project conversations, sidebar history loading, recent-50 window issues, and local `state_5.sqlite` history visibility problems.

如果你遇到 Codex 历史对话“看起来丢了”，项目文件夹里的线程数量明显不对，或者普通对话只显示最近一小部分，可以把这个仓库地址发给 Codex，让它读取仓库并按这里的脚本自行排查和修复：

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

你可以直接对 Codex 说：

```text
请读取这个 GitHub 仓库：
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
然后按照里面的 README / scripts / skill，帮我修复 Codex Desktop 历史对话和项目对话显示不全的问题。
```

如果你已经把 `skill/` 安装到本地 Codex Skills，也可以说：

```text
用 $codex-history-recovery 修复 Codex 历史对话显示不全。
```

## 推荐提示词

如果你想让 Codex 更稳一点，不要一上来就直接改文件，可以把下面这段完整发给 Codex：

```text
请读取这个 GitHub 仓库：
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery

我遇到的问题是：Codex Desktop 左侧历史对话 / 项目对话显示不全。

请先和我对齐需求，确认你理解准确后再开始。
若关键信息不足，请先提问并让我确认。
请通过连续提问的方式和我头脑风暴，直到你对需求理解到位。

确认后，请按照仓库里的 README、scripts 和 skill 进行诊断和修复：
1. 先只读诊断，不要直接关闭 Codex。
2. 检查本地 SQLite 历史是否还在。
3. 判断是数据真的丢失，还是侧栏 recent thread 列表显示不全。
4. 若符合修复条件，再准备 patched Codex。
5. 生成补丁和桌面启动脚本后，先告诉我结果，让我确认是否重启应用。

输出后继续问我是否满意。
如果我不满意，请继续迭代，直到满足要求。
```

这段提示词不需要安装插件。Codex 只需要能读取 GitHub 仓库，并且能在你的本机运行脚本即可：Windows 使用 PowerShell，macOS 使用 bash。

如果你希望以后用一句 `$codex-history-recovery` 触发固定流程，再安装仓库里的 `skill/` 目录即可。Skill 是可选项，不是运行脚本的前置条件。

## 典型痛点

这个工具针对的是这类情况：

- 左侧普通对话列表变少，只剩最近几天或最近几周
- 项目文件夹里的历史线程数量明显少于实际数量
- 线程管理里能看到总线程数，但侧栏不显示
- 本地数据库里还有旧会话，但项目组里看不到
- SQLite 里有未归档线程，但它既不在项目映射、普通对话列表，也不在置顶列表
- Codex 更新后，之前修好的历史侧栏又失效
- 重启 Codex 后又变回“少历史”的状态，因为点到了官方版快捷方式、开始菜单或任务栏固定图标
- 置顶区、项目区、普通对话区的显示关系变乱
- 英文搜索里常见的 `Codex Desktop missing chat history`、`project conversations disappeared`、`No chats`、`sidebar hides older conversations`、`recent-50 window`、`state_5.sqlite local data intact`

这个问题最折磨人的地方是：UI 看起来像历史丢了，但实际上数据可能还在。

## 重启后又变回去了怎么办

如果刚修好时能看到历史，重新启动 Codex 后又变回“只显示一部分”，优先检查是不是启动到了官方版，而不是 patched 版。

在 Windows 上，官方版进程路径通常长这样：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__...\app\Codex.exe
```

patched 版进程路径应该长这样：

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>\app\Codex.exe
```

这个坑很常见：补丁包还在，历史数据也还在，但用户从桌面原来的 `Codex.lnk`、开始菜单、任务栏固定图标或托盘重新打开了官方版。官方版没有侧栏全量历史补丁，所以看起来像“又丢了”。

推荐做法：

1. 运行生成的 `start-codex-patched-history.cmd`
2. 使用脚本自动生成的 `Codex 历史修复版` 快捷方式
3. 如果你经常点原来的 `Codex` 图标，Windows 可加 `-PromoteLauncherShortcuts`，脚本会先备份官方快捷方式，再把桌面和开始菜单里的 `Codex` 指向修复启动器
4. 如果任务栏固定图标仍然打开官方版，取消固定旧图标，再从 `Codex 历史修复版` 重新固定

这不是历史再次丢失，而是启动入口绕过了补丁。

## 搜索关键词

如果你是通过搜索找到这里，这些关键词描述的是同一类问题：

- Codex Desktop missing chat history
- Codex Desktop project conversations disappeared
- Codex Desktop sidebar history missing
- Codex Desktop project chats show No chats
- Codex Desktop hides older conversations
- Codex Desktop recent-50 window
- Codex Desktop local data intact
- Codex `state_5.sqlite` threads still exist
- Codex project history recovery
- Codex conversation history recovery
- Codex sidebar full workspace history

## 核心判断

先不要急着重装 Codex，也不要先怀疑账号、provider、模型配置或中转站。

在这个问题里，真正的关键通常是：

> 本地 SQLite 历史还在，但 Codex Desktop 左侧侧栏没有把完整 thread 列表喂给项目分组。

Codex Desktop 的项目组并不是直接扫描 SQLite 里的全部历史，而是先拿一份“最近会话 ID 列表”，再按项目分组。

如果旧线程没有进入这个 recent 列表，即使它还在本地数据库中，也不会显示在左侧项目文件夹里。

另一种常见情况是：SQLite 里有未归档线程，但 `.codex-global-state.json` 里的 `thread-project-assignments`、`projectless-thread-ids` 和 `pinned-thread-ids` 都没有包含它。这样的线程也会变成“本地存在，但侧栏无归属”。

## 修复思路

本工具会复制一份本地 Codex Desktop 应用包，然后只修改复制版里的前端侧栏加载逻辑。

核心修复是把侧栏刷新入口从单页 recent 列表：

```js
listRecentThreads(...)
```

改为全量 active thread 列表：

```js
this.listAllThreads({ modelProviders: null, archived: false })
```

这样项目分组能拿到完整线程列表，再按 Codex 原本的项目分配和 `updated_at` 排序逻辑展示。

启动 patched Codex 前，Windows 启动器还会运行一次全局可见分区修复：先备份 `.codex-global-state.json`，再把“未归档但无侧栏归属”的线程按它们自己的 `cwd` 补回项目区或普通对话区。

## 它不会做什么

这个工具不会：

- 上传你的历史对话
- 删除你的 Codex 历史数据库
- 重写 `%USERPROFILE%\.codex\state_5.sqlite`
- 无备份地清空或重写 `%USERPROFILE%\.codex\.codex-global-state.json`
- 分发 Codex 官方应用文件
- 分发 patched `app.asar`

它做的是本地复制、本地解包、本地打补丁、本地重新打包。

如果发现全局状态里有“无侧栏归属”的未归档线程，它会先备份 `.codex-global-state.json`，再做很窄的补齐：补 `thread-project-assignments`、`projectless-thread-ids`、`thread-workspace-root-hints` 和对应排序/展开状态，不修改会话正文。

## 推荐用法：让 Codex 自己跑

最简单的方式不是手动看脚本，而是把仓库地址发给 Codex：

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

然后让 Codex 做这几件事：

1. 读取仓库说明
2. 运行只读诊断
3. 检查本地 SQLite 线程数量
4. 复制当前 Codex Desktop 安装包
5. 解包 `app.asar`
6. 应用全量历史侧栏补丁
7. 补齐全局可见分区里的漏网线程
8. 生成 `app.asar.patched`
9. 生成桌面启动脚本
10. 由你确认后重启 patched Codex

这样做的好处是：Codex 会根据你当前机器环境判断路径、版本和状态，不需要你手动猜。

## 手动使用方式

如果你想自己运行，也可以。

### Windows

先运行只读诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -DiagnoseOnly
```

准备修复包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1
```

如果 Codex Desktop 刚更新过，建议强制重新复制最新版本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -ForceRefresh
```

如果修好后重启又变回去，通常是点到了官方快捷方式。可以让脚本生成醒目的补丁版快捷方式，并可选择把桌面/开始菜单的默认 `Codex` 快捷方式改成修复启动器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

使用 `-PromoteLauncherShortcuts` 时，脚本会先备份原快捷方式，再改入口；不会删除官方 Codex 应用。

Windows 脚本会生成桌面启动器：

```text
start-codex-patched-history.cmd
```

运行这个启动器时，它会关闭当前 Codex 进程、修复全局可见会话分区、应用 pending `app.asar.patched`，再启动 patched Codex。

### macOS

先运行只读诊断：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --diagnose-only
```

准备修复包：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh
```

如果 Codex Desktop 刚更新过，建议强制重新复制最新版本：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --force-refresh
```

如果脚本没有自动找到 Codex.app，可以手动指定：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --codex-app "/Applications/Codex.app"
```

macOS 脚本会生成桌面启动器：

```text
start-codex-patched-history.command
```

运行这个启动器时，它会关闭当前 Codex 进程、应用 pending `app.asar.patched`，再启动 patched Codex。

## 为什么不默认自动关闭 Codex

关闭 Codex 会断开当前对话。

所以脚本默认只准备补丁，不主动杀进程。等确认补丁已经生成，再由你运行桌面启动器应用补丁。

如果你确认可以立刻重启，可以加：

```powershell
-ApplyNow
```

## Codex Skill 用法

仓库里也带了一个 Skill：

```text
skill/
  SKILL.md
  agents/openai.yaml
  scripts/repair_codex_history_sidebar.ps1
  scripts/repair_codex_history_sidebar_macos.sh
```

把 `skill/` 复制到：

```text
%USERPROFILE%\.codex\skills\codex-history-recovery
```

然后在 Codex 里说：

```text
用 $codex-history-recovery 修复 Codex 历史对话显示不全。
```

Codex 就会按固定流程诊断、打补丁、生成启动脚本。

## 适用边界

这个工具适用于：

- Windows / macOS 版 Codex Desktop
- 本地 SQLite 里线程还在，但侧栏显示不全
- Codex 更新后需要重新套历史侧栏补丁

如果本地 SQLite 数据库本身已经损坏或被删除，这个工具不能凭空恢复不存在的数据。

## 免责声明

这是一个非官方本地排障和修复工具，不是 OpenAI 官方工具。

Codex Desktop 更新后，前端打包文件名或代码结构可能变化，补丁可能需要重新适配。使用前建议先让 Codex 跑 `-DiagnoseOnly`，确认本地历史数据仍然存在。
