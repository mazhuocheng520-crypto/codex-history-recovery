# Codex Desktop History Recovery

Fix missing Codex Desktop chat history, hidden project conversations, recent sidebar limits, and local `state_5.sqlite` visibility issues on Windows and macOS.

中文说明在前，English version below.

Repository:

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

## 中文说明

这是一个给 Codex Desktop 历史对话显示异常准备的本地修复方案。

它解决的不是“云端同步账号切换”问题，而是这类情况：

- 左侧普通对话只剩最近一小部分
- 项目文件夹里的对话数量明显不对
- 线程管理里能看到总线程数，但侧栏不显示
- 本地 `state_5.sqlite` 里还有线程，但项目组或普通对话里看不到
- Codex 更新后，之前修好的历史侧栏又失效
- 修好后重启又变回去，因为打开了官方版快捷方式，而不是补丁版启动器

### 最简单用法

把这个仓库地址发给 Codex：

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

然后对 Codex 说：

```text
请读取这个 GitHub 仓库：
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery

按照里面的 README、scripts 和 skill，帮我修复 Codex Desktop 历史对话和项目对话显示不全的问题。
先做只读诊断，确认本地历史数据还在，再生成修复包和启动器。
不要直接关闭当前 Codex，等我确认后再重启应用。
```

### 核心判断

先不要急着重装 Codex，也不要先怀疑账号、provider、模型配置或中转站。

这个问题通常是：

> 本地 SQLite 历史还在，但 Codex Desktop 左侧侧栏没有把完整 thread 列表交给项目分组。

项目组不是直接扫描 SQLite 全量历史，而是先拿一份 recent thread 列表，再按项目分组。旧线程没进入 recent 列表时，即使数据仍然存在，也不会出现在左侧项目文件夹里。

另一种情况是 `.codex-global-state.json` 里没有给未归档线程分配到项目、普通对话或置顶区。脚本会先备份全局状态，再做很窄的补齐。

### 修复思路

脚本会复制一份本机 Codex Desktop 应用包，只修改复制版里的侧栏加载逻辑。

核心补丁是把侧栏刷新从单页 recent 列表：

```js
listRecentThreads(...)
```

改成全量 active thread 列表：

```js
this.listAllThreads({ modelProviders: null, archived: false })
```

这样项目分组可以拿到完整线程列表，再按 Codex 原本的项目分配和 `updated_at` 排序显示。

### 重启后又变回去

如果刚修好时能看到历史，重启后又只显示一部分，通常不是历史再次丢失，而是打开了官方版 Codex。

Windows 上，官方版路径通常是：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__...\app\Codex.exe
```

补丁版路径应该在：

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>\app\Codex.exe
```

正确入口：

- `start-codex-patched-history.cmd`
- `Codex 历史修复版.lnk`

如果你经常点原来的 `Codex` 图标，可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

这个参数会先备份官方快捷方式，再把桌面和开始菜单里的 `Codex` 指向修复启动器。任务栏固定图标如果仍打开官方版，需要取消固定旧图标，再从 `Codex 历史修复版` 重新固定。

### Windows 手动命令

只读诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -DiagnoseOnly
```

准备修复包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1
```

Codex 刚更新后，强制重新复制最新版：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -ForceRefresh
```

修复默认快捷方式入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

脚本会生成：

```text
%USERPROFILE%\Desktop\start-codex-patched-history.cmd
```

运行它会关闭当前 Codex、修复可见会话分区、应用 pending `app.asar.patched`，再启动 patched Codex。

### macOS 手动命令

只读诊断：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --diagnose-only
```

准备修复包：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh
```

Codex 刚更新后，强制重新复制最新版：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --force-refresh
```

手动指定 Codex.app：

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --codex-app "/Applications/Codex.app"
```

脚本会生成：

```text
~/Desktop/start-codex-patched-history.command
```

### 不会做什么

这个工具不会：

- 上传你的历史对话
- 删除你的 Codex 历史数据库
- 重写 `%USERPROFILE%\.codex\state_5.sqlite`
- 无备份地清空 `%USERPROFILE%\.codex\.codex-global-state.json`
- 分发 Codex 官方应用文件
- 分发 patched `app.asar`

它做的是本地复制、本地解包、本地打补丁、本地重新打包。

## English Version

This repository provides a local recovery workflow for Codex Desktop sidebar history issues.

It is for cases where:

- ordinary chats only show a recent subset
- project folders show fewer conversations than expected
- thread management shows the threads, but the sidebar does not
- local `state_5.sqlite` still contains threads, but the sidebar cannot display them
- a Codex Desktop update removed a previously working patch
- history worked once, then disappeared again after restarting through the official app shortcut

### Quick Use

Send this repository URL to Codex:

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

Then ask:

```text
Read this GitHub repository:
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery

Use its README, scripts, and skill to repair missing Codex Desktop chat history and project conversations.
Start with read-only diagnosis, confirm that local history still exists, then prepare the patched app and launcher.
Do not close the current Codex session until I confirm the restart.
```

### Root Cause

The usual issue is not deleted data.

The local SQLite history still exists, but the Codex Desktop sidebar gives project grouping only a limited recent thread list. Older threads outside that recent list can remain in `state_5.sqlite` while disappearing from the project sidebar.

Another case is a missing visible assignment in `.codex-global-state.json`: an active thread exists locally, but is not assigned to a project, ordinary chats, or pinned chats.

### Fix Strategy

The scripts copy the local Codex Desktop app and patch only the copied bundle.

The core frontend change replaces a paginated recent-thread refresh:

```js
listRecentThreads(...)
```

with a full active-thread refresh:

```js
this.listAllThreads({ modelProviders: null, archived: false })
```

This lets project grouping receive the complete active thread list before applying Codex's existing project assignment and `updated_at` ordering.

### If It Reverts After Restart

If the fix worked once but history disappears again after restarting, you probably launched the official Codex app instead of the patched launcher.

On Windows, the official app usually runs from:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__...\app\Codex.exe
```

The patched app should run from:

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>\app\Codex.exe
```

Use one of these patched entry points:

- `start-codex-patched-history.cmd`
- `Codex 历史修复版.lnk`

To redirect the default Windows desktop and Start Menu `Codex` shortcuts to the recovery launcher, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

This backs up the original shortcuts first. If a taskbar pinned icon still opens the official app, unpin it and pin the patched shortcut again.

### Windows Commands

Read-only diagnosis:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -DiagnoseOnly
```

Prepare the patched app:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1
```

After a Codex Desktop update:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -ForceRefresh
```

Promote patched shortcuts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

### macOS Commands

Read-only diagnosis:

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --diagnose-only
```

Prepare the patched app:

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh
```

After a Codex Desktop update:

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --force-refresh
```

Specify Codex.app manually:

```bash
bash ./scripts/repair_codex_history_sidebar_macos.sh --codex-app "/Applications/Codex.app"
```

### Safety

This tool does not upload chat history, delete `state_5.sqlite`, or distribute Codex application files.

It performs local copy, local unpack, local patch, and local repack only.

## Keywords

- Codex Desktop missing chat history
- Codex Desktop project conversations disappeared
- Codex Desktop sidebar history missing
- Codex Desktop recent thread limit
- Codex Desktop recent-50 window
- Codex Desktop local data intact
- Codex `state_5.sqlite` recovery
- Codex project history recovery
- Codex conversation history recovery
- Codex patched sidebar launcher

## Disclaimer

This is an unofficial local troubleshooting and recovery workflow. Codex Desktop updates may change bundled frontend files, so the patch may need to be rebuilt or adapted after updates.
