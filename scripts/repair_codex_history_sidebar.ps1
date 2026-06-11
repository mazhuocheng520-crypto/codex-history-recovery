[CmdletBinding()]
param(
    [string]$WorkRoot = (Join-Path $env:USERPROFILE 'Documents\Codex\history-audit'),
    [string]$CodexInstallRoot = '',
    [int]$SidebarLimit = 1000,
    [int]$RecentPageCount = 20,
    [switch]$DiagnoseOnly,
    [switch]$ForceRefresh,
    [switch]$ApplyNow,
    [switch]$PromoteLauncherShortcuts
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
        if ($updated -eq $text) {
            $historyLimitPattern = 'let ([A-Za-z_$][A-Za-z0-9_$]*)=this\.params\.getHistoryLimit\?\.\(\)\?\?50,([A-Za-z_$][A-Za-z0-9_$]*)=\1>50,([A-Za-z_$][A-Za-z0-9_$]*)=\2\?\1:50\*this\.recentConversationPageCount,([A-Za-z_$][A-Za-z0-9_$]*)=performance\.now\(\),([A-Za-z_$][A-Za-z0-9_$]*)=await this\.listRecentThreads\(\{limit:\3,cursor:null,useStateDbOnly:\2\}\);'
            $historyLimitReplacement = 'let $1=this.params.getHistoryLimit?.()??50,$2=!0,$3=$1,$4=performance.now(),$5={data:await this.listAllThreads({modelProviders:null,archived:!1}),nextCursor:null};'
            $updated = [regex]::Replace($text, $historyLimitPattern, $historyLimitReplacement, 1)
        }
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

function Write-Shortcut {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$LauncherPath,
        [Parameter(Mandatory)][string]$PatchedExe,
        [string]$BackupPath = ''
    )
    if ($BackupPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath $BackupPath)) {
        Copy-Item -LiteralPath $Path -Destination $BackupPath -Force
        Write-Host "Existing shortcut backed up: $BackupPath"
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $LauncherPath
    $shortcut.WorkingDirectory = Split-Path -Parent $LauncherPath
    if (Test-Path -LiteralPath $PatchedExe) {
        $shortcut.IconLocation = "$PatchedExe,0"
    }
    $shortcut.Description = 'Start patched Codex with history/sidebar recovery'
    $shortcut.Save()
    Write-Host "Shortcut written: $Path"
}

function Write-LauncherShortcuts {
    param(
        [Parameter(Mandatory)][string]$LauncherPath,
        [Parameter(Mandatory)][string]$PatchedExe,
        [bool]$PromoteDefault = $false
    )
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

        Write-Shortcut -Path (Join-Path $desktop 'Codex 历史修复版.lnk') -LauncherPath $LauncherPath -PatchedExe $PatchedExe
        Write-Shortcut -Path (Join-Path $startMenu 'Codex 历史修复版.lnk') -LauncherPath $LauncherPath -PatchedExe $PatchedExe

        if ($PromoteDefault) {
            Write-Shortcut -Path (Join-Path $desktop 'Codex.lnk') -LauncherPath $LauncherPath -PatchedExe $PatchedExe -BackupPath (Join-Path $desktop 'Codex 官方版.lnk')
            Write-Shortcut -Path (Join-Path $startMenu 'Codex.lnk') -LauncherPath $LauncherPath -PatchedExe $PatchedExe -BackupPath (Join-Path $startMenu 'Codex 官方版.lnk')
        }
    } catch {
        Write-Host "Shortcut creation skipped: $($_.Exception.Message)"
    }
}

function Write-LauncherShortcuts {
    param(
        [Parameter(Mandatory)][string]$LauncherPath,
        [Parameter(Mandatory)][string]$PatchedExe,
        [bool]$PromoteDefault = $false
    )
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        $historyShortcutName = 'Codex ' + [string][char]0x5386 + [string][char]0x53F2 + [string][char]0x4FEE + [string][char]0x590D + [string][char]0x7248 + '.lnk'
        $officialShortcutName = 'Codex ' + [string][char]0x5B98 + [string][char]0x65B9 + [string][char]0x7248 + '.lnk'

        Write-Shortcut -Path (Join-Path $desktop $historyShortcutName) -LauncherPath $LauncherPath -PatchedExe $PatchedExe
        Write-Shortcut -Path (Join-Path $startMenu $historyShortcutName) -LauncherPath $LauncherPath -PatchedExe $PatchedExe

        if ($PromoteDefault) {
            Write-Shortcut -Path (Join-Path $startMenu 'Codex.lnk') -LauncherPath $LauncherPath -PatchedExe $PatchedExe -BackupPath (Join-Path $startMenu $officialShortcutName)
        }
    } catch {
        Write-Host "Shortcut creation skipped: $($_.Exception.Message)"
    }
}

function Write-Launcher {
    param(
        [Parameter(Mandatory)][string]$PatchedExe,
        [Parameter(Mandatory)][string]$PatchedAsar,
        [Parameter(Mandatory)][string]$PendingAsar,
        [Parameter(Mandatory)][string]$LauncherDir,
        [string]$StateRepairScript = '',
        [bool]$PromoteDefaultShortcuts = $false
    )
    $launcherNames = @('start-codex-patched-history.cmd', 'start-codex-patched-sidebar-1000.cmd')
    $launcherPs1 = Join-Path $LauncherDir 'start-codex-patched-history.ps1'
    $logPath = Join-Path $LauncherDir 'last-history-launch.log'
    $ps1Template = @'
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PatchedExe = '__PATCHED_EXE__'
$PatchedAsar = '__PATCHED_ASAR__'
$NextAsar = '__PENDING_ASAR__'
$StateRepair = '__STATE_REPAIR__'
$LogPath = '__LAUNCH_LOG__'

function Write-LaunchLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    $line | Tee-Object -FilePath $LogPath -Append
}

function Get-CodexProcesses {
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -in @('Codex.exe', 'codex.exe') } |
        Select-Object ProcessId, Name, ExecutablePath, CommandLine, CreationDate
}

if (Test-Path -LiteralPath $LogPath) {
    Remove-Item -LiteralPath $LogPath -Force
}

Write-LaunchLog 'Starting patched Codex history launcher.'

if (-not (Test-Path -LiteralPath $PatchedExe)) {
    throw "Patched Codex.exe not found: $PatchedExe"
}

$before = @(Get-CodexProcesses)
Write-LaunchLog "Codex processes before close: $($before.Count)"
foreach ($proc in $before) {
    Write-LaunchLog "Closing pid=$($proc.ProcessId) name=$($proc.Name) exe=$($proc.ExecutablePath)"
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 3

$left = @(Get-CodexProcesses)
if ($left.Count -gt 0) {
    foreach ($proc in $left) {
        Write-LaunchLog "Retry taskkill pid=$($proc.ProcessId) name=$($proc.Name)"
        & taskkill.exe /PID $proc.ProcessId /T /F | ForEach-Object { Write-LaunchLog $_ }
    }
    Start-Sleep -Seconds 2
}

$left = @(Get-CodexProcesses)
if ($left.Count -gt 0) {
    foreach ($proc in $left) {
        Write-LaunchLog "Still running pid=$($proc.ProcessId) name=$($proc.Name) exe=$($proc.ExecutablePath)"
    }
    throw "Codex processes are still running; cannot safely repair state_5.sqlite."
}

if ($StateRepair.Trim().Length -gt 0 -and (Test-Path -LiteralPath $StateRepair)) {
    Write-LaunchLog 'Repairing Codex global visible thread state and SQLite integrity.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $StateRepair *>&1 |
        ForEach-Object { Write-LaunchLog $_.ToString() }
    if ($LASTEXITCODE -ne 0) {
        throw "State repair failed with exit code $LASTEXITCODE"
    }
}

if (Test-Path -LiteralPath $NextAsar) {
    Write-LaunchLog 'Applying pending app.asar patch.'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $PatchedAsar -Destination ($PatchedAsar + '.backup-before-history-' + $stamp) -Force
    Move-Item -LiteralPath $NextAsar -Destination $PatchedAsar -Force
}

Write-LaunchLog "Starting patched Codex: $PatchedExe"
Start-Process -FilePath $PatchedExe -WorkingDirectory (Split-Path -Parent $PatchedExe)
Write-LaunchLog 'Done.'
'@
    $ps1Content = $ps1Template.
        Replace('__PATCHED_EXE__', $PatchedExe.Replace("'", "''")).
        Replace('__PATCHED_ASAR__', $PatchedAsar.Replace("'", "''")).
        Replace('__PENDING_ASAR__', $PendingAsar.Replace("'", "''")).
        Replace('__STATE_REPAIR__', $StateRepairScript.Replace("'", "''")).
        Replace('__LAUNCH_LOG__', $logPath.Replace("'", "''"))

    $content = @"
@echo off
setlocal
set "LAUNCHER_PS1=$launcherPs1"

if not exist "%LAUNCHER_PS1%" (
  echo Launcher PowerShell script not found:
  echo %LAUNCHER_PS1%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER_PS1%"
if errorlevel 1 (
  echo.
  echo Codex history launcher failed. See:
  echo $logPath
  pause
  exit /b 1
)

exit /b 0
"@
    New-Item -ItemType Directory -Path $LauncherDir -Force | Out-Null
    Set-Content -LiteralPath $launcherPs1 -Value $ps1Content -Encoding ASCII
    Write-Host "Launcher script written: $launcherPs1"
    foreach ($name in $launcherNames) {
        $path = Join-Path $LauncherDir $name
        Set-Content -LiteralPath $path -Value $content -Encoding ASCII
        Write-Host "Launcher written: $path"
    }
    Write-LauncherShortcuts -LauncherPath (Join-Path $LauncherDir 'start-codex-patched-history.cmd') -PatchedExe $PatchedExe -PromoteDefault $PromoteDefaultShortcuts
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
    Write-Launcher -PatchedExe $patchedExe -PatchedAsar $asar -PendingAsar $pendingAsar -LauncherDir $WorkRoot -StateRepairScript $stateRepairScript -PromoteDefaultShortcuts $PromoteLauncherShortcuts

    $serverFile = Get-ChildItem -LiteralPath $assets -Filter 'app-server-manager-signals-*.js' |
        Where-Object { (Get-Content -Raw -LiteralPath $_.FullName).Contains('async runRecentConversationRefresh') } |
        Select-Object -First 1
    $serverText = Get-Content -Raw -LiteralPath $serverFile.FullName
    if ($serverText.Contains('async runRecentConversationRefresh') -and $serverText.Contains('listAllThreads({modelProviders:null,archived:!1})')) {
        Write-Host 'full-refresh-patch-ok'
    } else {
        throw 'full-refresh-patch-missing'
    }

    $pending = Get-Item -LiteralPath $pendingAsar
    Write-Host "Pending asar: $($pending.FullName)"
    Write-Host "Pending asar size: $($pending.Length)"
    Write-Host "Patched root: $patchedRoot"

    if ($ApplyNow) {
        $launcher = Join-Path $WorkRoot 'start-codex-patched-history.cmd'
        Start-Process -FilePath $launcher -WindowStyle Hidden
    }
}

if ($DiagnoseOnly) {
    Show-HistoryState
    exit 0
}

Invoke-Repair
