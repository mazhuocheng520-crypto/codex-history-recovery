# Codex History Recovery

修复 Windows 版 Codex Desktop 左侧历史对话、项目对话显示不全的问题。

如果你遇到 Codex 历史对话“看起来丢了”，项目文件夹里的线程数量明显不对，或者普通对话只显示最近一小部分，可以把这个仓库地址发给 Codex，让它读取仓库并按这里的脚本自行排查和修复：

```text
https://github.com/mazhuocheng520-crypto/codex-history-recovery
```

你可以直接对 Codex 说：

```text
请读取这个 GitHub 仓库：
https://github.com/mazhuocheng520-crypto/codex-history-recovery
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
https://github.com/mazhuocheng520-crypto/codex-history-recovery

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

这段提示词不需要安装插件。Codex 只需要能读取 GitHub 仓库，并且能在你的本机运行 PowerShell 脚本。

如果你希望以后用一句 `$codex-history-recovery` 触发固定流程，再安装仓库里的 `skill/` 目录即可。Skill 是可选项，不是运行脚本的前置条件。

## 典型痛点

这个工具针对的是这类情况：

- 左侧普通对话列表变少，只剩最近几天或最近几周
- 项目文件夹里的历史线程数量明显少于实际数量
- 线程管理里能看到总线程数，但侧栏不显示
- 本地数据库里还有旧会话，但项目组里看不到
- Codex 更新后，之前修好的历史侧栏又失效
- 置顶区、项目区、普通对话区的显示关系变乱

这个问题最折磨人的地方是：UI 看起来像历史丢了，但实际上数据可能还在。

## 核心判断

先不要急着重装 Codex，也不要先怀疑账号、provider、模型配置或中转站。

在这个问题里，真正的关键通常是：

> 本地 SQLite 历史还在，但 Codex Desktop 左侧侧栏没有把完整 thread 列表喂给项目分组。

Codex Desktop 的项目组并不是直接扫描 SQLite 里的全部历史，而是先拿一份“最近会话 ID 列表”，再按项目分组。

如果旧线程没有进入这个 recent 列表，即使它还在本地数据库中，也不会显示在左侧项目文件夹里。

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

## 它不会做什么

这个工具不会：

- 上传你的历史对话
- 删除你的 Codex 历史数据库
- 重写 `%USERPROFILE%\.codex\state_5.sqlite`
- 重写 `%USERPROFILE%\.codex\.codex-global-state.json`
- 分发 Codex 官方应用文件
- 分发 patched `app.asar`

它做的是本地复制、本地解包、本地打补丁、本地重新打包。

## 推荐用法：让 Codex 自己跑

最简单的方式不是手动看脚本，而是把仓库地址发给 Codex：

```text
https://github.com/mazhuocheng520-crypto/codex-history-recovery
```

然后让 Codex 做这几件事：

1. 读取仓库说明
2. 运行只读诊断
3. 检查本地 SQLite 线程数量
4. 复制当前 Codex Desktop 安装包
5. 解包 `app.asar`
6. 应用全量历史侧栏补丁
7. 生成 `app.asar.patched`
8. 生成桌面启动脚本
9. 由你确认后重启 patched Codex

这样做的好处是：Codex 会根据你当前机器环境判断路径、版本和状态，不需要你手动猜。

## 手动使用方式

如果你想自己运行，也可以。

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

脚本会生成桌面启动器：

```text
start-codex-patched-history.cmd
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

- Windows 版 Codex Desktop
- 本地 SQLite 里线程还在，但侧栏显示不全
- Codex 更新后需要重新套历史侧栏补丁

如果本地 SQLite 数据库本身已经损坏或被删除，这个工具不能凭空恢复不存在的数据。

## 免责声明

这是一个非官方本地排障和修复工具，不是 OpenAI 官方工具。

Codex Desktop 更新后，前端打包文件名或代码结构可能变化，补丁可能需要重新适配。使用前建议先让 Codex 跑 `-DiagnoseOnly`，确认本地历史数据仍然存在。
