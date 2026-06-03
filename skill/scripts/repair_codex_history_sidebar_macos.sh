#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="$HOME/Documents/Codex/history-audit"
CODEX_APP=""
SIDEBAR_LIMIT="1000"
RECENT_PAGE_COUNT="20"
DIAGNOSE_ONLY="0"
FORCE_REFRESH="0"
APPLY_NOW="0"

usage() {
  cat <<'EOF'
Usage: repair_codex_history_sidebar_macos.sh [options]

Options:
  --diagnose-only              Print local Codex history counts only.
  --force-refresh              Re-copy the currently installed Codex.app before patching.
  --apply-now                  Run the generated launcher after preparing the patch.
  --work-root PATH             Output root for patched app copy.
  --codex-app PATH             Path to Codex.app. Defaults to auto-detect.
  --sidebar-limit N            Sidebar list limit to patch. Default: 1000.
  --recent-page-count N        Recent conversation page count. Default: 20.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diagnose-only) DIAGNOSE_ONLY="1"; shift ;;
    --force-refresh) FORCE_REFRESH="1"; shift ;;
    --apply-now) APPLY_NOW="1"; shift ;;
    --work-root) WORK_ROOT="$2"; shift 2 ;;
    --codex-app) CODEX_APP="$2"; shift 2 ;;
    --sidebar-limit) SIDEBAR_LIMIT="$2"; shift 2 ;;
    --recent-page-count) RECENT_PAGE_COUNT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

full_path() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

assert_under_path() {
  local path root full root_full
  path="$(full_path "$1")"
  root="$(full_path "$2")"
  full="$path"
  root_full="${root%/}/"
  case "$full/" in
    "$root_full"*) ;;
    *) echo "Refusing to modify path outside intended root: $full" >&2; exit 1 ;;
  esac
}

diagnose_history() {
  local db="$HOME/.codex/state_5.sqlite"
  local state="$HOME/.codex/.codex-global-state.json"
  echo "Codex DB: $db"
  echo "Global state: $state"
  if [[ ! -f "$db" ]]; then
    echo "state_5.sqlite not found."
    return
  fi
  need_cmd python3
  python3 - <<'PY'
import json, os, sqlite3
from collections import Counter
home = os.path.expanduser("~")
db = os.path.join(home, ".codex", "state_5.sqlite")
state = os.path.join(home, ".codex", ".codex-global-state.json")
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
rows = list(con.execute("select id, cwd, title, created_at, updated_at, archived from threads"))
print("SQLite threads:", len(rows))
print("Archived counts:", dict(Counter(r["archived"] for r in rows)))
print("CWD counts:")
for cwd, count in Counter((r["cwd"] or "<null>") for r in rows).most_common(20):
    print(f"  {count:4d}  {cwd}")
if os.path.exists(state):
    data = json.load(open(state, "r", encoding="utf-8"))
    assignments = data.get("thread-project-assignments") or {}
    projectless = data.get("projectless-thread-ids") or []
    pinned = data.get("pinned-thread-ids") or []
    print("Project assignments:", len(assignments))
    print("Projectless IDs:", len(projectless))
    print("Pinned IDs:", len(pinned))
con.close()
PY
}

find_codex_app() {
  if [[ -n "$CODEX_APP" ]]; then
    [[ -d "$CODEX_APP" ]] || { echo "Codex app not found: $CODEX_APP" >&2; exit 1; }
    full_path "$CODEX_APP"
    return
  fi

  local candidates=(
    "/Applications/Codex.app"
    "/Applications/OpenAI Codex.app"
    "$HOME/Applications/Codex.app"
    "$HOME/Applications/OpenAI Codex.app"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" && -f "$candidate/Contents/Resources/app.asar" ]]; then
      full_path "$candidate"
      return
    fi
  done

  while IFS= read -r candidate; do
    if [[ -d "$candidate" && -f "$candidate/Contents/Resources/app.asar" ]]; then
      full_path "$candidate"
      return
    fi
  done < <(find /Applications "$HOME/Applications" -maxdepth 1 -name '*Codex*.app' -type d 2>/dev/null || true)

  echo "Could not auto-detect Codex.app. Pass --codex-app /path/to/Codex.app." >&2
  exit 1
}

codex_version() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    version="$(date +%Y%m%d-%H%M%S)"
  fi
  echo "$version"
}

asar_cmd() {
  local tool_root="$HOME/Documents/Codex/asar-tools"
  local asar="$tool_root/node_modules/.bin/asar"
  if [[ -x "$asar" ]]; then
    echo "$asar"
    return
  fi
  need_cmd npm
  mkdir -p "$tool_root"
  npm --prefix "$tool_root" install @electron/asar
  [[ -x "$asar" ]] || { echo "Failed to install asar tool at $asar" >&2; exit 1; }
  echo "$asar"
}

patch_assets() {
  local assets="$1"
  need_cmd python3
  python3 - "$assets" "$SIDEBAR_LIMIT" "$RECENT_PAGE_COUNT" <<'PY'
import pathlib, re, sys
assets = pathlib.Path(sys.argv[1])
sidebar_limit = sys.argv[2]
recent_page_count = sys.argv[3]

def patch_file(path, fn):
    text = path.read_text(encoding="utf-8")
    updated = fn(text)
    if updated != text:
        path.write_text(updated, encoding="utf-8")

server = None
for p in assets.glob("app-server-manager-signals-*.js"):
    text = p.read_text(encoding="utf-8")
    if "async runRecentConversationRefresh" in text:
        server = p
        break
if server is None:
    raise SystemExit("Could not find app-server-manager-signals asset.")

def patch_server(text):
    pattern = r"let ([A-Za-z_$][A-Za-z0-9_$]*)=await this\.listRecentThreads\(\{limit:[^}]+,cursor:null\}\);this\.fetchedRecentConversations=!0,this\.nextRecentConversationCursor=\1\.nextCursor;"
    replacement = r"let \1={data:await this.listAllThreads({modelProviders:null,archived:!1}),nextCursor:null};this.fetchedRecentConversations=!0,this.nextRecentConversationCursor=null;"
    updated, count = re.subn(pattern, replacement, text, count=1)
    if count == 0 and "listAllThreads({modelProviders:null,archived:!1})" not in text:
        raise SystemExit("runRecentConversationRefresh patch pattern was not found.")
    updated = re.sub(r"recentConversationPageCount=\d+;", f"recentConversationPageCount={recent_page_count};", updated)
    updated = updated.replace("limit:50,cursor:this.nextRecentConversationCursor", f"limit:{sidebar_limit},cursor:this.nextRecentConversationCursor")
    updated = updated.replace("limit:50*this.recentConversationPageCount", "limit:500*this.recentConversationPageCount")
    updated = updated.replace("limit:200,cursor:a,sortKey:e.recentConversationsSortKey", f"limit:{sidebar_limit},cursor:a,sortKey:e.recentConversationsSortKey")
    return updated

patch_file(server, patch_server)

for p in assets.glob("app-main-*.js"):
    text = p.read_text(encoding="utf-8")
    if "var gT=" not in text and "inbox-items" not in text:
        continue
    def patch_main(text):
        updated = re.sub(r"var gT=\d+,", f"var gT={sidebar_limit},", text)
        updated = re.sub(r"var nT=\d+;", f"var nT={sidebar_limit};", updated)
        updated = re.sub(r"inbox-items`,\{limit:\d+\}", f"inbox-items`,{{limit:{sidebar_limit}}}", updated)
        return updated
    patch_file(p, patch_main)

for p in assets.glob("sidebar-thread-list-signals-*.js"):
    text = p.read_text(encoding="utf-8")
    if "inbox-items" not in text:
        continue
    def patch_sidebar(text):
        return re.sub(r"inbox-items`,\{params:\{limit:\d+\}", f"inbox-items`,{{params:{{limit:{sidebar_limit}}}", text)
    patch_file(p, patch_sidebar)
PY
}

write_launcher() {
  local patched_app="$1"
  local patched_asar="$2"
  local pending_asar="$3"
  local launcher="$HOME/Desktop/start-codex-patched-history.command"
  cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail
PATCHED_APP="$patched_app"
PATCHED_ASAR="$patched_asar"
NEXT_ASAR="$pending_asar"

osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1 || true
pkill -x Codex >/dev/null 2>&1 || true
pkill -x codex >/dev/null 2>&1 || true
sleep 3

if [[ -f "\$NEXT_ASAR" ]]; then
  stamp="\$(date +%Y%m%d-%H%M%S)"
  cp "\$PATCHED_ASAR" "\$PATCHED_ASAR.backup-before-history-\$stamp"
  mv "\$NEXT_ASAR" "\$PATCHED_ASAR"
fi

open "\$PATCHED_APP"
EOF
  chmod +x "$launcher"
  echo "Launcher written: $launcher"
}

repair() {
  need_cmd python3
  local app version patched_root patched_app unpacked resources asar pending asar_tool assets
  app="$(find_codex_app)"
  version="$(codex_version "$app")"
  patched_root="$WORK_ROOT/patched-codex-$version-macos"
  patched_app="$patched_root/$(basename "$app")"
  unpacked="$patched_root/app_asar_unpacked"
  resources="$patched_app/Contents/Resources"
  asar="$resources/app.asar"
  pending="$resources/app.asar.patched"

  mkdir -p "$WORK_ROOT"
  assert_under_path "$patched_root" "$WORK_ROOT"

  if [[ ! -d "$patched_app" || "$FORCE_REFRESH" == "1" ]]; then
    rm -rf "$patched_app"
    mkdir -p "$patched_root"
    cp -R "$app" "$patched_app"
  fi

  [[ -f "$asar" ]] || { echo "app.asar not found: $asar" >&2; exit 1; }
  asar_tool="$(asar_cmd)"
  rm -rf "$unpacked"
  "$asar_tool" extract "$asar" "$unpacked"

  assets="$unpacked/webview/assets"
  patch_assets "$assets"

  "$asar_tool" pack "$unpacked" "$pending"
  write_launcher "$patched_app" "$asar" "$pending"

  if grep -q 'listAllThreads({modelProviders:null,archived:!1})' "$assets"/app-server-manager-signals-*.js; then
    echo "full-refresh-patch-ok"
  else
    echo "full-refresh-patch-missing" >&2
    exit 1
  fi
  echo "Pending asar: $pending"
  echo "Patched app: $patched_app"

  if [[ "$APPLY_NOW" == "1" ]]; then
    open "$HOME/Desktop/start-codex-patched-history.command"
  fi
}

if [[ "$DIAGNOSE_ONLY" == "1" ]]; then
  diagnose_history
  exit 0
fi

repair
