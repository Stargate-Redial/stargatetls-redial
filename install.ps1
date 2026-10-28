<#
.SYNOPSIS
    Installs the Stargate Redial bots (Botrix) into the Source mod described by mod.psd1.

.DESCRIPTION
    Copies the bot plugin, its settings and waypoints, and the "Redial" menu background into the mod's folder
    (Steam\steamapps\sourcemods\<mod>), and adds a bot block to the mod's cfg files. For StargateTC 2 it also
    installs the in-game server browser fix into Source SDK Base. Every replaced file is backed up in a
    "redial-backup" folder; uninstall.bat puts everything back. Running it again is safe.

.PARAMETER ModDir
    The mod's folder, if it isn't found (e.g. "C:\Program Files (x86)\Steam\steamapps\sourcemods\stargatetc2").

.PARAMETER SdkBaseDir
    The Source SDK Base folder the mod runs on, if it isn't found (StargateTC 2 only).

.PARAMETER NoServerBrowserFix
    StargateTC 2: don't install the server browser fix into Source SDK Base.

.PARAMETER NoSplash
    Keep the mod's own menu background.
#>
param(
    [string]$ModDir,
    [string]$SdkBaseDir,
    [switch]$NoServerBrowserFix,
    [switch]$NoSplash
)

. (Join-Path $PSScriptRoot 'redial-common.ps1')
$Mod = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'mod.psd1')
$Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -TotalCount 1).Trim()
$Payload = Join-Path $PSScriptRoot 'payload'

Write-Host "$($Mod.Title) $Version installer"
Write-Host ''

if (-not (Test-Path -LiteralPath (Join-Path $Payload $Mod.PluginDll))) {
    Stop-Redial ("$($Mod.PluginDll) is missing. Download the release zip from the Releases page " +
                 "($($Mod.Releases)), not the source code.")
}

# 1. Find the mod (and Source SDK Base).
$steam = Get-SteamDir
if (-not $ModDir) {
    $sm = Get-SourceModsDir $steam
    if ($sm) { $ModDir = Join-Path $sm $Mod.ModFolder }
}
if (-not $ModDir -or -not (Test-Path -LiteralPath (Join-Path $ModDir 'gameinfo.txt'))) {
    Stop-Redial ("$($Mod.ModName) not found (looked for $ModDir\gameinfo.txt). Install the mod first, or pass " +
                 "-ModDir ""<path>\steamapps\sourcemods\$($Mod.ModFolder)"".")
}
$ModDir = [IO.Path]::GetFullPath($ModDir).TrimEnd('\')
Write-Step "Mod: $ModDir"

$sdk = $null
if ($Mod.SdkBaseFolder) {
    $sdk = $SdkBaseDir
    if (-not $sdk) { $sdk = Find-SdkBase $steam $Mod.SdkBaseFolder }
    if (-not $sdk -or -not (Test-Path -LiteralPath (Join-Path $sdk 'bin\engine.dll'))) {
        Stop-Redial ("$($Mod.SdkBaseFolder) not found. Install it from Steam (steam://install/$($Mod.SdkAppId)), " +
                     "or pass -SdkBaseDir ""<path>\steamapps\common\$($Mod.SdkBaseFolder)"".")
    }
    $sdk = [IO.Path]::GetFullPath($sdk).TrimEnd('\')
    Write-Step "$($Mod.SdkBaseFolder): $sdk"
}

$sdkLocked = $null
if ($Mod.ServerBrowserFix -and -not $NoServerBrowserFix) { $sdkLocked = $sdk }
$running = Get-RunningGame $ModDir $sdkLocked
if ($running) {
    Stop-Redial "The game is running ($($running.ExecutablePath), process $($running.ProcessId)). Close it, then run the installer again."
}

# 2. Bot plugin, settings, waypoints, menu background.
$files = @(Get-ChildItem -LiteralPath $Payload -Recurse -File | ForEach-Object { $_.FullName.Substring($Payload.Length + 1) })
if ($NoSplash) { $files = @($files | Where-Object { $_ -notlike 'materials\*' }) }
$r = Install-Files $Payload $ModDir $files
Write-Step ("Bots installed: {0} files added, {1} replaced (originals in {2}\{3}), {4} already up to date." -f
    $r.Added, $r.Replaced, $Mod.ModFolder, $BackupFolder, $r.Same)

# 3. addons\botrix.vdf. The episode1 engine (StargateTC 2) loads plugins relative to <Source SDK Base>\bin.
if ($Mod.VdfFromSdkBin) {
    $plugin = Get-RelativePath (Join-Path $sdk 'bin') (Join-Path $ModDir 'addons\botrix')
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('redial-vdf-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'addons') | Out-Null
    $vdf = @(
        '"Plugin"',
        '{',
        "`t// The Source 2006 engine loads plugins relative to <Source SDK Base>\bin. Written by install.bat.",
        "`t""file""`t""$plugin""",
        '}')
    [IO.File]::WriteAllLines((Join-Path $tmp 'addons\botrix.vdf'), [string[]]$vdf, $Latin1)
    Install-Files $tmp $ModDir @('addons\botrix.vdf') | Out-Null
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Write-Step "Plugin path (addons\botrix.vdf): $plugin"
    if ($plugin -match '^[A-Za-z]:') {
        Write-Note "The mod and $($Mod.SdkBaseFolder) are on different drives: if the bots don't load, move one of them."
    }
}

# 4. Bot settings in the mod's cfg files.
$map = Read-Manifest $ModDir
foreach ($cfg in $Mod.CfgFiles) {
    if (Set-CfgBlock (Join-Path $ModDir $cfg) $Mod.CfgBlock) { $map[$cfg] = 'C' }
}
Write-Manifest $ModDir $map
Write-Step ("Bot settings added to " + ($Mod.CfgFiles -join ', ') + '.')

# 5. StargateTC 2: the in-game server browser fix.
if ($Mod.ServerBrowserFix) {
    if ($NoServerBrowserFix) {
        Write-Step 'Server browser fix: skipped (-NoServerBrowserFix).'
    } else {
        $zip = Join-Path $PSScriptRoot 'server-browser-fix\Server-browser-fix.zip'
        if ((Get-Md5 $zip) -ne $Mod.ServerBrowserFixMd5) { Stop-Redial "$zip is damaged (MD5 mismatch). Download the release again." }
        $done = $true
        foreach ($k in $Mod.ServerBrowserFixFiles.Keys) {
            $f = Join-Path $sdk $k
            if (-not (Test-Path -LiteralPath $f) -or (Get-Md5 $f) -ne $Mod.ServerBrowserFixFiles[$k]) { $done = $false }
        }
        if ($done) {
            Write-Step 'Server browser fix: already installed.'
        } else {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('redial-sbfix-' + [guid]::NewGuid())
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp
            $src = Join-Path $tmp 'Server-browser-fix'
            $fixFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object { $_.FullName.Substring($src.Length + 1) })
            $r = Install-Files $src $sdk $fixFiles
            Remove-Item -LiteralPath $tmp -Recurse -Force
            Write-Step ("Server browser fix installed in {0}: {1} files added, {2} replaced (originals in {3})." -f
                $Mod.SdkBaseFolder, $r.Added, $r.Replaced, $BackupFolder)
        }
    }
}

Write-Host ''
Write-Host "Done. Start $($Mod.ModName) from Steam (restart Steam if it isn't in your library yet), then:"
Write-Host "  - Create Server: bots join and fill the game up to 10 players;"
Write-Host "  - or join the 24/7 server: connect $($Mod.PublicServer)"
Write-Host "Community: $($Mod.Discord)"
exit 0
