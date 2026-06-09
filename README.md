# Codex 历史对话恢复工具

用于修复 Codex Desktop 左侧历史对话丢失、项目对话显示不全、旧会话不进侧栏、`state_5.sqlite` 本地历史仍在但 UI 看不到的问题。支持 Windows 和 macOS。

英文说明保留在下方，方便搜索：English summary is included below for search.

仓库地址：

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

## 这个工具解决什么

它解决的不是云端同步、账号切换、provider 或模型配置问题，而是 Codex Desktop 本地历史仍在、侧栏没有完整展示的问题。

典型表现：

- 普通对话只显示最近一小部分
- 项目文件夹里的对话数量明显少于实际数量
- 线程管理里能看到总线程数，但左侧侧栏不显示
- 本地 `state_5.sqlite` 里有线程，但项目组或普通对话里看不到
- Codex 更新后，之前修好的历史侧栏又失效
- 修好后重启又变回去，因为打开了官方版快捷方式，而不是补丁版启动器

## 最简单用法

把这个仓库地址发给 Codex：

```text
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery
```

然后直接说：

```text
请读取这个 GitHub 仓库：
https://github.com/mazhuocheng520-crypto/codex-desktop-history-recovery

按照里面的 README、scripts 和 skill，帮我修复 Codex Desktop 历史对话和项目对话显示不全的问题。
先做只读诊断，确认本地历史数据还在，再生成修复包和启动器。
不要直接关闭当前 Codex，等我确认后再重启应用。
```

## 核心判断

先不要急着重装 Codex，也不要先怀疑账号、provider、模型配置或中转站。

这个问题通常是：

> 本地 SQLite 历史还在，但 Codex Desktop 左侧侧栏没有把完整 thread 列表交给项目分组。

Codex Desktop 的项目组不是直接扫描 SQLite 全量历史，而是先拿一份 recent thread 列表，再按项目分组。旧线程没有进入 recent 列表时，即使数据仍然存在，也不会出现在左侧项目文件夹里。

另一种情况是 `.codex-global-state.json` 里没有把未归档线程分配到项目、普通对话或置顶区。脚本会先备份全局状态，再做很窄的补齐。

## 修复原理

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

## 重启后又变回去

如果刚修好时能看到历史，重启后又只显示一部分，通常不是历史再次丢失，而是打开了官方版 Codex。

Windows 上官方版路径通常是：

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

实际启动器放在修复目录里，桌面只保留快捷方式：

```text
%USERPROFILE%\Documents\Codex\history-audit\start-codex-patched-history.cmd
```

如果你经常点原来的 `Codex` 图标，可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

这个参数会先备份官方快捷方式，再把桌面和开始菜单里的 `Codex` 指向修复启动器。任务栏固定图标如果仍打开官方版，需要取消固定旧图标，再从 `Codex 历史修复版` 重新固定。

## Windows 命令

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
%USERPROFILE%\Documents\Codex\history-audit\start-codex-patched-history.cmd
```

运行它会关闭当前 Codex、修复可见会话分区、应用 pending `app.asar.patched`，再启动 patched Codex。桌面只需要保留 `Codex 历史修复版.lnk` 快捷方式。

## macOS 命令

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

## 安全边界

这个工具不会：

- 上传你的历史对话
- 删除你的 Codex 历史数据库
- 重写 `%USERPROFILE%\.codex\state_5.sqlite`
- 无备份地清空 `%USERPROFILE%\.codex\.codex-global-state.json`
- 分发 Codex 官方应用文件
- 分发 patched `app.asar`

它做的是本地复制、本地解包、本地打补丁、本地重新打包。

## Skill 用法

仓库里包含一个可选 Skill：

```text
skill/
```

复制到：

```text
%USERPROFILE%\.codex\skills\codex-history-recovery
```

然后在 Codex 里说：

```text
用 $codex-history-recovery 修复 Codex 历史对话显示不全。
```

## English Summary

This repository fixes Codex Desktop sidebar history visibility issues where local `state_5.sqlite` still contains conversations, but ordinary chats or project conversations do not appear in the UI.

Common symptoms:

- missing Codex Desktop chat history
- hidden project conversations
- project folders show too few threads
- sidebar only shows recent conversations
- local `state_5.sqlite` data is intact
- the fix worked once but disappeared after launching the official app shortcut

The scripts copy the local Codex Desktop app and patch only the copied bundle. The core change replaces a paginated recent-thread refresh with a full active-thread refresh:

```js
this.listAllThreads({ modelProviders: null, archived: false })
```

Windows shortcut recovery:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -PromoteLauncherShortcuts
```

## 搜索关键词

- Codex 历史对话丢失
- Codex 项目对话不显示
- Codex 左侧侧栏历史不全
- Codex 普通对话只显示最近
- Codex Desktop missing chat history
- Codex Desktop project conversations disappeared
- Codex Desktop sidebar history missing
- Codex Desktop recent thread limit
- Codex `state_5.sqlite` recovery
- Codex conversation history recovery

## 免责声明

这是非官方本地排障和修复方案。Codex Desktop 更新后，前端打包文件名或代码结构可能变化，补丁可能需要重新适配。
