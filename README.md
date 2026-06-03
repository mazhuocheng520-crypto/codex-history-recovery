# Codex History Recovery

一个用于修复 Windows 版 Codex Desktop 左侧历史对话 / 项目对话显示不全的本地修复工具。

> 非官方工具。它不会上传、删除或重写你的 Codex 历史数据库；它只会复制一份本地 Codex 应用包，在复制出来的版本里修改侧栏历史加载逻辑。

## 解决什么问题

有些 Codex Desktop 用户会遇到：

- 左侧普通对话列表只显示最近一部分
- 项目文件夹里的历史线程数量明显变少
- 线程管理里能看到总数，但侧栏不显示
- 旧会话还在本地数据库里，却没有进入左侧项目分组
- 应用更新后，之前修好的侧栏又失效

这个问题的关键不一定是历史真的丢了，而可能是侧栏前端只拿到了一份被截断的 recent thread 列表。

## 修复思路

Codex Desktop 的项目组并不是直接扫描 SQLite 里的全部历史，而是先拿“最近会话 ID 列表”，再按项目分组。

如果旧线程没有进入这个 recent 列表，即使它还在本地数据库里，也不会显示在左侧项目文件夹中。

本工具会把侧栏刷新入口从单页 recent 列表改成全量 active thread 列表：

```js
this.listAllThreads({ modelProviders: null, archived: false })
```

这样项目分组能拿到完整线程列表，再按 Codex 原本的项目分配和 `updated_at` 逻辑排序。

## 不会做什么

本工具不会：

- 上传你的历史对话
- 删除 `%USERPROFILE%\.codex\state_5.sqlite`
- 修改 `%USERPROFILE%\.codex\.codex-global-state.json`
- 分发 patched `app.asar`
- 分发 Codex 官方应用文件

## 使用方式

先运行只读诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -DiagnoseOnly
```

准备修复包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1
```

如果 Codex 官方应用更新过，建议强制重新复制最新版本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair_codex_history_sidebar.ps1 -ForceRefresh
```

脚本会生成桌面启动器：

```text
start-codex-patched-history.cmd
```

运行这个启动器时，它会关闭当前 Codex 进程、应用 pending `app.asar.patched`，再启动 patched Codex。

## 为什么不自动关闭 Codex

关闭 Codex 会断开当前对话。为了避免修复过程打断正在进行的排查，脚本默认只准备补丁，不自动杀进程。

如果你确认可以立刻重启，可以加：

```powershell
-ApplyNow
```

## 目录说明

```text
scripts/
  repair_codex_history_sidebar.ps1

skill/
  SKILL.md
  agents/openai.yaml
  scripts/repair_codex_history_sidebar.ps1
```

`skill/` 目录可以复制到：

```text
%USERPROFILE%\.codex\skills\codex-history-recovery
```

然后你可以在 Codex 里用：

```text
用 $codex-history-recovery 修复 Codex 历史对话显示不全
```

## 发布注意

公开仓库里不要包含：

- `app.asar`
- `app.asar.patched`
- `app_asar_unpacked/`
- `patched-codex-*`
- `state_5.sqlite`
- `.codex-global-state.json`
- 含有个人项目名、对话标题、截图、账号信息的日志

## 免责声明

这是一个本地排障和修复脚本，不是 OpenAI 官方工具。Codex Desktop 更新后，前端打包文件名或代码结构可能变化，补丁可能需要重新适配。
