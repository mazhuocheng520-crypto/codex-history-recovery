---
name: codex-history-recovery
description: 修复 Codex Desktop 历史对话丢失、项目对话显示不全、普通对话只剩最近记录、更新后补丁失效，或修好后重启又打开官方版入口的问题。Windows/macOS 均可用。
---

# Codex 历史对话恢复

## 使用场景

当 Codex Desktop 本地线程数据还在，但左侧普通对话或项目文件夹显示不全时，使用这个 Skill。

典型情况：

- 历史对话看起来丢了
- 项目文件夹里的线程数量少于实际数量
- 普通对话只剩最近几天或几周
- Codex 更新后补丁失效
- 修好后重启又变回去，因为启动到了官方版 Codex

## 使用流程

1. 先做只读诊断，除非用户明确要求直接应用已知修复。

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1" -DiagnoseOnly
```

macOS:

```bash
bash "$HOME/.codex/skills/codex-history-recovery/scripts/repair_codex_history_sidebar_macos.sh" --diagnose-only
```

2. 准备或重建 patched Codex。

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1"
```

macOS:

```bash
bash "$HOME/.codex/skills/codex-history-recovery/scripts/repair_codex_history_sidebar_macos.sh"
```

Codex 官方应用更新后，Windows 使用 `-ForceRefresh`，macOS 使用 `--force-refresh`，强制复制最新安装包后重新打补丁。

3. 应用补丁时运行生成的桌面启动器。不要在用户未确认前主动关闭当前 Codex，因为启动器会结束 Codex 进程。

Windows:

```powershell
& "$env:USERPROFILE\Desktop\start-codex-patched-history.cmd"
```

macOS:

```bash
open "$HOME/Desktop/start-codex-patched-history.command"
```

## 重启后又失效

如果用户说“刚才修好了，重启后又没了”，先检查当前运行路径，不要急着重建补丁。

Windows 官方版路径通常是：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__...
```

patched 版路径应该在：

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>
```

如果当前进程是官方版，说明用户从原桌面快捷方式、开始菜单、任务栏固定图标或托盘入口打开了官方 Codex。直接让用户改用生成的启动器，不要从头排查数据库。

Windows 脚本会在修复目录生成启动器，并在桌面生成快捷方式：

```text
%USERPROFILE%\Documents\Codex\history-audit\start-codex-patched-history.cmd
Codex 历史修复版.lnk
```

如果用户希望桌面和开始菜单里的默认 `Codex` 也指向修复启动器，在确认后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1" -PromoteLauncherShortcuts
```

## 修复内容

保留用户 SQLite 历史。不要删除或重写：

- `%USERPROFILE%\.codex\state_5.sqlite`
- SQLite 行引用的 rollout 文件

启动器可以在备份后更新：

```text
%USERPROFILE%\.codex\.codex-global-state.json
```

只补齐缺失的可见侧栏归属：`thread-project-assignments`、`projectless-thread-ids`、`pinned-thread-ids`。不要清空或重建整个全局状态文件。

只修改复制出来的 Codex 应用包：

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>
```

核心前端补丁是把 `runRecentConversationRefresh` 改成使用：

```js
this.listAllThreads({modelProviders:null,archived:!1})
```

代替单页 `listRecentThreads(...)`。这样项目分组能拿到完整 active thread 列表。

## 验证点

准备补丁后检查：

- 输出包含 `full-refresh-patch-ok`
- patched app 的 `app\resources` 下存在 `app.asar.patched`
- 修复目录里的启动器指向 patched `Codex.exe`
- 修复目录里的启动器包含 `Repairing Codex global visible thread state`
- Windows 上存在 `Codex 历史修复版.lnk`

用户通过启动器重启后，再确认项目文件夹和普通对话是否显示完整历史。

如果补丁后仍然少，再检查 app-server 的 `thread/list` 是否本身遗漏旧 thread。下一步是 SQLite-backed sidebar adapter，不是 provider 切换或配置修改。
