[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PythonCommand {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$python = Get-PythonCommand
if (-not $python) {
    throw 'Python was not found; cannot repair Codex global visibility state.'
}

$code = @'
import datetime
import json
import os
import shutil
import sqlite3

home = os.path.expanduser("~")
db_path = os.path.join(home, ".codex", "state_5.sqlite")
state_path = os.path.join(home, ".codex", ".codex-global-state.json")
backup_root = os.path.join(home, ".codex", "backups_state", "visible-gap-project-assignments")
default_chat_root = os.path.normcase(os.path.join(home, "Documents", "Codex"))

def strip_extended(path):
    if not path:
        return ""
    if path.startswith("\\\\?\\"):
        return path[4:]
    return path

def canonical_project_id(path):
    bare = strip_extended(path)
    if not bare:
        return ""
    return path if path.startswith("\\\\?\\") else "\\\\?\\" + bare

if not os.path.exists(db_path):
    raise SystemExit("state_5.sqlite not found: " + db_path)
if not os.path.exists(state_path):
    raise SystemExit(".codex-global-state.json not found: " + state_path)

con = sqlite3.connect(db_path)
con.row_factory = sqlite3.Row
rows = list(con.execute(
    "select id, cwd, title, updated_at from threads where archived=0"
))
con.close()

with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)

assignments = state.setdefault("thread-project-assignments", {})
projectless = state.setdefault("projectless-thread-ids", [])
if not isinstance(projectless, list):
    projectless = list(projectless)
    state["projectless-thread-ids"] = projectless
pinned = state.get("pinned-thread-ids") or []
if not isinstance(pinned, list):
    pinned = list(pinned)

visible_ids = set(assignments) | set(projectless) | set(pinned)
missing = [r for r in rows if r["id"] not in visible_ids]

if not missing:
    print("visible-gap-ok")
    raise SystemExit(0)

stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
backup_dir = os.path.join(backup_root, stamp)
os.makedirs(backup_dir, exist_ok=True)
shutil.copy2(state_path, os.path.join(backup_dir, ".codex-global-state.json"))

expanded = state.setdefault("sidebar-expanded-groups", {})
project_orders = state.setdefault("sidebar-project-thread-orders", {})
project_order = state.setdefault("project-order", [])
hints = state.setdefault("thread-workspace-root-hints", {})

added_projects = 0
added_projectless = 0
for r in missing:
    thread_id = r["id"]
    cwd = r["cwd"] or ""
    bare_cwd = strip_extended(cwd)
    if not bare_cwd or os.path.normcase(bare_cwd) == default_chat_root:
        projectless.append(thread_id)
        hints[thread_id] = bare_cwd or default_chat_root
        added_projectless += 1
        continue

    project_id = canonical_project_id(cwd)
    assignments[thread_id] = {
        "projectKind": "local",
        "projectId": project_id,
    }
    hints[thread_id] = project_id
    project_orders.setdefault(project_id, {"sortKey": "updated_at"})
    expanded[project_id] = True
    expanded[bare_cwd] = True
    if project_id not in project_order and bare_cwd not in project_order:
        project_order.append(project_id)
    added_projects += 1

state["sidebar-chat-thread-order"] = {"sortKey": "updated_at"}

tmp_path = state_path + ".visible-gap-tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, separators=(",", ":"))
os.replace(tmp_path, state_path)

print(f"visible-gap-repaired project={added_projects} projectless={added_projectless} backup={backup_dir}")
'@

$code | & $python -
