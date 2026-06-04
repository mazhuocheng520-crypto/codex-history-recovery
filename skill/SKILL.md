---
name: codex-history-recovery
description: Restore missing Codex Desktop sidebar history and project conversations on Windows or macOS. Use when Codex history appears incomplete, project folders show too few threads, ordinary chats only show recent weeks, or a Codex app update requires rebuilding the local patched history fix.
---

# Codex History Recovery

## Workflow

Use this skill for the Codex Desktop history/sidebar issue where local thread data still exists but the left sidebar or project groups show too few conversations.

1. Diagnose first unless the user explicitly asks to apply the known fix.

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1" -DiagnoseOnly
```

macOS:

```bash
bash "$HOME/.codex/skills/codex-history-recovery/scripts/repair_codex_history_sidebar_macos.sh" --diagnose-only
```

2. Prepare or rebuild the patched Codex copy.

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-history-recovery\scripts\repair_codex_history_sidebar.ps1"
```

macOS:

```bash
bash "$HOME/.codex/skills/codex-history-recovery/scripts/repair_codex_history_sidebar_macos.sh"
```

Use `-ForceRefresh` on Windows or `--force-refresh` on macOS after an official Codex update so the script copies the newest installed app before patching.

3. Apply the pending patch by running the generated desktop launcher. Do not close the current Codex conversation automatically unless the user explicitly agrees, because the launcher terminates Codex processes:

```powershell
& "$env:USERPROFILE\Desktop\start-codex-patched-history.cmd"
```

macOS:

```bash
open "$HOME/Desktop/start-codex-patched-history.command"
```

## What The Fix Does

Preserve the user's SQLite history. Do not delete or rewrite:

- `%USERPROFILE%\.codex\state_5.sqlite`
- rollout files referenced by the SQLite rows

The launcher may update `%USERPROFILE%\.codex\.codex-global-state.json` only after creating a backup, and only to add active threads that are missing from all visible sidebar buckets (`thread-project-assignments`, `projectless-thread-ids`, and `pinned-thread-ids`). Do not clear or rebuild the whole global state file.

Patch only the copied Codex app bundle under:

```text
%USERPROFILE%\Documents\Codex\history-audit\patched-codex-<version>
```

The core frontend patch changes `runRecentConversationRefresh` so the sidebar refresh uses:

```js
this.listAllThreads({modelProviders:null,archived:!1})
```

instead of a single paginated `listRecentThreads(...)` call. This makes project grouping receive the full active thread list before applying project assignments. Keep the stock relative time display unless the user specifically asks for exact timestamps.

The Windows launcher also runs `repair_codex_global_visible_state.ps1` before starting the patched app. This repairs the narrower case where SQLite contains active threads, but the global sidebar state does not assign them to a project, ordinary chats, or pinned chats.

## Validation

After preparing the patch, check for:

- `full-refresh-patch-ok`
- `app.asar.patched` exists under the patched app's `app\resources`
- the generated desktop launcher points to the patched `Codex.exe`
- the generated desktop launcher includes `Repairing Codex global visible thread state`

After the user restarts through the launcher, ask them to verify that project folders and ordinary chats now show the expected historical conversations. If a fresh diagnosis shows higher counts than older expected numbers, use the current SQLite and global-state counts instead of stale expected numbers.

If conversations are still missing after this patch, inspect whether the app-server `thread/list` method itself is omitting rows. The next escalation is a direct SQLite-backed sidebar adapter, not provider switching or config changes.
