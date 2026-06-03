---
name: codex-history-recovery
description: Restore missing Codex Desktop sidebar history and project conversations on Windows. Use when Codex history appears incomplete, project folders show too few threads, ordinary chats only show recent weeks, or a Codex app update requires rebuilding the local patched history fix.
---

# Codex History Recovery

## Workflow

Use this skill for the Windows Codex Desktop history/sidebar issue where local thread data still exists but the left sidebar or project groups show too few conversations.

1. Diagnose first unless the user explicitly asks to apply the known fix:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1" -DiagnoseOnly
```

2. Prepare or rebuild the patched Codex copy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1"
```

Use `-ForceRefresh` after an official Codex update so the script copies the newest installed app before patching.

3. Apply the pending patch by running the generated desktop launcher. Do not close the current Codex conversation automatically unless the user explicitly agrees, because the launcher terminates Codex processes:

```powershell
& "$env:USERPROFILE\Desktop\start-codex-patched-history.cmd"
```

## What The Fix Does

Preserve the user's SQLite history and global state. Do not delete or rewrite:

- `%USERPROFILE%\.codex\state_5.sqlite`
- `%USERPROFILE%\.codex\.codex-global-state.json`
- rollout files referenced by the SQLite rows

Patch only the copied Codex app bundle under:

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>
```

The core frontend patch changes `runRecentConversationRefresh` so the sidebar refresh uses:

```js
this.listAllThreads({modelProviders:null,archived:!1})
```

instead of a single paginated `listRecentThreads(...)` call. This makes project grouping receive the full active thread list before applying project assignments. Keep the stock relative time display unless the user specifically asks for exact timestamps.

## Validation

After preparing the patch, check for:

- `full-refresh-patch-ok`
- `app.asar.patched` exists under the patched app's `app\resources`
- the generated desktop launcher points to the patched `Codex.exe`

After the user restarts through the launcher, ask them to verify that project folders and ordinary chats now show the expected historical conversations.

If conversations are still missing after this patch, inspect whether the app-server `thread/list` method itself is omitting rows. The next escalation is a direct SQLite-backed sidebar adapter, not provider switching or config changes.
