[CmdletBinding()]
param(
    [string]$WorkRoot = (Join-Path $env:USERPROFILE 'Documents\Codex\history-audit'),
    [string]$CodexInstallRoot = '',
    [int]$SidebarLimit = 1000,
    [int]$RecentPageCount = 20,
    [switch]$DiagnoseOnly,
    [switch]$ForceRefresh,
    [switch]$ApplyNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-UnderPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent
    )
    $full = Get-FullPath $Path
    $root = (Get-FullPath $Parent).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside intended root: $full"
    }
}

function Get-PythonCommand {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Show-HistoryState {
    $db = Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
    $state = Join-Path $env:USERPROFILE '.codex\.codex-global-state.json'
    Write-Host "Codex DB: $db"
    Write-Host "Global state: $state"
    if (-not (Test-Path -LiteralPath $db)) {
        Write-Host "state_5.sqlite not found."
        return
    }
    $python = Get-PythonCommand
    if (-not $python) {
        Write-Host "Python not found; skipping SQLite summary."
        return
    }
    $code = @'
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
for cwd, count in Counter((r["cwd"] or "<null>").replace("\\\\?\\", "") for r in rows).most_common(20):
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
'@
    $code | & $python -
}

function Find-CodexInstallRoot {
    if ($CodexInstallRoot.Trim().Length -gt 0) {
        $resolved = Get-FullPath $CodexInstallRoot
        if (-not (Test-Path -LiteralPath $resolved)) {
            throw "CodexInstallRoot not found: $resolved"
        }
        return $resolved
    }

    $windowsApps = 'C:\Program Files\WindowsApps'
    $candidates = Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'OpenAI.Codex_*_x64__2p2nqsd0c76g0' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'app\Codex.exe') }

    if (-not $candidates) {
        throw "Could not find OpenAI.Codex in $windowsApps. Pass -CodexInstallRoot explicitly."
    }

    return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Get-CodexVersionFromPath {
    param([Parameter(Mandatory)][string]$Path)
    $name = Split-Path -Leaf $Path
    if ($name -match '^OpenAI\.Codex_([^_]+)_') {
        return $Matches[1]
    }
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-AsarCommand {
    $toolRoot = Join-Path $env:USERPROFILE 'Documents\Codex\asar-tools'
    $asar = Join-Path $toolRoot 'node_modules\.bin\asar.cmd'
    if (Test-Path -LiteralPath $asar) {
        return $asar
    }

    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if (-not $npm) {
        throw "npm was not found; cannot install @electron/asar."
    }

    New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
    & $npm.Source --prefix $toolRoot install '@electron/asar'
    if (-not (Test-Path -LiteralPath $asar)) {
        throw "Failed to install asar tool at $asar"
    }
    return $asar
}

function Copy-CodexApp {
    param(
        [Parameter(Mandatory)][string]$SourceApp,
        [Parameter(Mandatory)][string]$DestinationApp,
        [Parameter(Mandatory)][string]$SafeRoot
    )
    Assert-UnderPath -Path $DestinationApp -Parent $SafeRoot
    if (Test-Path -LiteralPath $DestinationApp) {
        if (-not $ForceRefresh) { return }
        Remove-Item -LiteralPath $DestinationApp -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationApp) -Force | Out-Null
    Copy-Item -LiteralPath $SourceApp -Destination $DestinationApp -Recurse -Force
}

function Patch-TextFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Patch
    )
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $newText = & $Patch $text
    if ($newText -ne $text) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $newText, $utf8NoBom)
    }
}

function Patch-AppServerManager {
    param([Parameter(Mandatory)][string]$AssetsDir)
    $files = Get-ChildItem -LiteralPath $AssetsDir -Filter 'app-server-manager-signals-*.js'
    $target = $files | Where-Object { ([System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)).Contains('async runRecentConversationRefresh') } | Select-Object -First 1
    if (-not $target) { throw "Could not find app-server-manager-signals asset." }

    Patch-TextFile -Path $target.FullName -Patch {
        param($text)
        $pattern = 'let ([A-Za-z_$][A-Za-z0-9_$]*)=await this\.listRecentThreads\(\{limit:[^}]+,cursor:null\}\);this\.fetchedRecentConversations=!0,this\.nextRecentConversationCursor=\1\.nextCursor;'
        $replacement = 'let $1={data:await this.listAllThreads({modelProviders:null,archived:!1}),nextCursor:null};this.fetchedRecentConversations=!0,this.nextRecentConversationCursor=null;'
        $updated = [regex]::Replace($text, $pattern, $replacement, 1)
        if ($updated -eq $text -and -not $text.Contains('listAllThreads({modelProviders:null,archived:!1})')) {
            throw "runRecentConversationRefresh patch pattern was not found."
        }
        $updated = [regex]::Replace($updated, 'recentConversationPageCount=\d+;', "recentConversationPageCount=$RecentPageCount;")
        $updated = $updated.Replace('limit:50,cursor:this.nextRecentConversationCursor', "limit:$SidebarLimit,cursor:this.nextRecentConversationCursor")
        $updated = $updated.Replace('limit:50*this.recentConversationPageCount', "limit:500*this.recentConversationPageCount")
        $updated = $updated.Replace('limit:200,cursor:a,sortKey:e.recentConversationsSortKey', "limit:$SidebarLimit,cursor:a,sortKey:e.recentConversationsSortKey")
        return $updated
    }
}

function Patch-MainAssets {
    param([Parameter(Mandatory)][string]$AssetsDir)
    $mainFiles = Get-ChildItem -LiteralPath $AssetsDir -Filter 'app-main-*.js'
    foreach ($file in $mainFiles) {
        $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        if (-not ($raw.Contains('var gT=') -or $raw.Contains('inbox-items'))) { continue }
        Patch-TextFile -Path $file.FullName -Patch {
            param($text)
            $updated = [regex]::Replace($text, 'var gT=\d+,', "var gT=$SidebarLimit,")
            $updated = [regex]::Replace($updated, 'var nT=\d+;', "var nT=$SidebarLimit;")
            $updated = [regex]::Replace($updated, 'inbox-items`,\{limit:\d+\}', ('inbox-items`,{limit:' + $SidebarLimit + '}'))
            return $updated
        }
    }

    $sidebarFiles = Get-ChildItem -LiteralPath $AssetsDir -Filter 'sidebar-thread-list-signals-*.js'
    foreach ($file in $sidebarFiles) {
        $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        if (-not $raw.Contains('inbox-items')) { continue }
        Patch-TextFile -Path $file.FullName -Patch {
            param($text)
            return [regex]::Replace($text, 'inbox-items`,\{params:\{limit:\d+\}', ('inbox-items`,{params:{limit:' + $SidebarLimit + '}'))
        }
    }
}

function Write-Launcher {
    param(
        [Parameter(Mandatory)][string]$PatchedExe,
        [Parameter(Mandatory)][string]$PatchedAsar,
        [Parameter(Mandatory)][string]$PendingAsar,
        [string]$StateRepairScript = ''
    )
    $desktop = [Environment]::GetFolderPath('Desktop')
    $launcherNames = @('start-codex-patched-history.cmd', 'start-codex-patched-sidebar-1000.cmd')
    $stateRepairLine = ''
    $stateRepairBlock = ''
    if ($StateRepairScript.Trim().Length -gt 0 -and (Test-Path -LiteralPath $StateRepairScript)) {
        $stateRepairLine = "set ""STATE_REPAIR=$StateRepairScript"""
        $stateRepairBlock = @"

if exist "%STATE_REPAIR%" (
  echo Repairing Codex global visible thread state...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%STATE_REPAIR%"
  if errorlevel 1 (
    echo Failed to repair Codex global visible thread state.
    pause
    exit /b 1
  )
)
"@
    }
    $content = @"
@echo off
setlocal

set "PATCHED_EXE=$PatchedExe"
set "PATCHED_ASAR=$PatchedAsar"
set "NEXT_ASAR=$PendingAsar"
$stateRepairLine

if not exist "%PATCHED_EXE%" (
  echo Patched Codex.exe not found:
  echo %PATCHED_EXE%
  pause
  exit /b 1
)

echo Closing existing Codex processes...
taskkill /IM Codex.exe /F >nul 2>nul
taskkill /IM codex.exe /F >nul 2>nul
timeout /t 3 /nobreak >nul
$stateRepairBlock

if exist "%NEXT_ASAR%" (
  echo Applying pending Codex history sidebar patch...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "`$asar='%PATCHED_ASAR%'; `$next='%NEXT_ASAR%'; `$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; Copy-Item -LiteralPath `$asar -Destination (`$asar + '.backup-before-history-' + `$stamp) -Force; Move-Item -LiteralPath `$next -Destination `$asar -Force"
  if errorlevel 1 (
    echo Failed to apply pending app.asar update.
    pause
    exit /b 1
  )
)

echo Starting patched Codex...
start "" "%PATCHED_EXE%"
exit /b 0
"@
    foreach ($name in $launcherNames) {
        $path = Join-Path $desktop $name
        Set-Content -LiteralPath $path -Value $content -Encoding ASCII
        Write-Host "Launcher written: $path"
    }
}

function Invoke-Repair {
    $installRoot = Find-CodexInstallRoot
    $version = Get-CodexVersionFromPath -Path $installRoot
    $patchedRoot = Join-Path $WorkRoot "patched-codex-$version"
    $sourceApp = Join-Path $installRoot 'app'
    $patchedApp = Join-Path $patchedRoot 'app'
    $unpacked = Join-Path $patchedRoot 'app_asar_unpacked'
    $resources = Join-Path $patchedApp 'resources'
    $asar = Join-Path $resources 'app.asar'
    $pendingAsar = Join-Path $resources 'app.asar.patched'
    $patchedExe = Join-Path $patchedApp 'Codex.exe'

    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    Copy-CodexApp -SourceApp $sourceApp -DestinationApp $patchedApp -SafeRoot $WorkRoot

    if (-not (Test-Path -LiteralPath $asar)) { throw "app.asar not found: $asar" }

    $asarCmd = Get-AsarCommand
    if (Test-Path -LiteralPath $unpacked) {
        Assert-UnderPath -Path $unpacked -Parent $patchedRoot
        Remove-Item -LiteralPath $unpacked -Recurse -Force
    }
    & $asarCmd extract $asar $unpacked

    $assets = Join-Path $unpacked 'webview\assets'
    Patch-AppServerManager -AssetsDir $assets
    Patch-MainAssets -AssetsDir $assets

    & $asarCmd pack $unpacked $pendingAsar
    $stateRepairScript = Join-Path $PSScriptRoot 'repair_codex_global_visible_state.ps1'
    if (-not (Test-Path -LiteralPath $stateRepairScript)) { $stateRepairScript = '' }
    Write-Launcher -PatchedExe $patchedExe -PatchedAsar $asar -PendingAsar $pendingAsar -StateRepairScript $stateRepairScript

    $serverFile = Get-ChildItem -LiteralPath $assets -Filter 'app-server-manager-signals-*.js' |
        Where-Object { (Get-Content -Raw -LiteralPath $_.FullName).Contains('async runRecentConversationRefresh') } |
        Select-Object -First 1
    $serverText = Get-Content -Raw -LiteralPath $serverFile.FullName
    if ($serverText.Contains('let t={data:await this.listAllThreads({modelProviders:null,archived:!1}),nextCursor:null};this.fetchedRecentConversations=!0,this.nextRecentConversationCursor=null;')) {
        Write-Host 'full-refresh-patch-ok'
    } else {
        throw 'full-refresh-patch-missing'
    }

    $pending = Get-Item -LiteralPath $pendingAsar
    Write-Host "Pending asar: $($pending.FullName)"
    Write-Host "Pending asar size: $($pending.Length)"
    Write-Host "Patched root: $patchedRoot"

    if ($ApplyNow) {
        $launcher = Join-Path ([Environment]::GetFolderPath('Desktop')) 'start-codex-patched-history.cmd'
        Start-Process -FilePath $launcher -WindowStyle Hidden
    }
}

if ($DiagnoseOnly) {
    Show-HistoryState
    exit 0
}

Invoke-Repair
