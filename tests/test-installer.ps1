<#
.SYNOPSIS
    Tests install.ps1 / uninstall.ps1 on a fake Steam layout in a temporary folder (nothing real is touched).

.DESCRIPTION
    Builds steamapps\sourcemods\<mod> (and steamapps\common\Source SDK Base for StargateTC 2) with dummy files,
    then: install, install again, uninstall, and checks that every original file is back and nothing is left.

    powershell -ExecutionPolicy Bypass -File tests\test-installer.ps1 -PackageDir <release folder> [-Shell pwsh]

.PARAMETER PackageDir
    A release folder: the scripts, mod.psd1, VERSION and payload\ with the plugin DLL (the extracted release zip).
#>
param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [ValidateSet('powershell', 'pwsh')][string]$Shell = 'powershell'
)
$ErrorActionPreference = 'Stop'
$PackageDir = [IO.Path]::GetFullPath($PackageDir)
$Mod = Import-PowerShellDataFile (Join-Path $PackageDir 'mod.psd1')
$script:Pass = 0
$script:Fail = 0
function Check([string]$What, [bool]$Ok) {
    if ($Ok) { $script:Pass++; Write-Host "  ok    $What" } else { $script:Fail++; Write-Host "  FAIL  $What" -ForegroundColor Red }
}
function Snapshot([string]$Root) {
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $h[$f.FullName.Substring($Root.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash
    }
    return $h
}
function Same-Snapshot($A, $B) {
    if ($A.Count -ne $B.Count) { return $false }
    foreach ($k in $A.Keys) { if (-not $B.ContainsKey($k) -or $B[$k] -ne $A[$k]) { return $false } }
    return $true
}
function Run([string]$Script, [string[]]$ScriptArgs, [string]$Package = $PackageDir) {
    # The scripts write their errors to stderr: not a failure of this test script.
    $ErrorActionPreference = 'Continue'
    $out = & $Shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Package $Script) @ScriptArgs 2>&1
    $script:LastOutput = ($out | Out-String)
    return $LASTEXITCODE
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('redial-test-' + [guid]::NewGuid())
$modDir = Join-Path $root ('Steam\steamapps\sourcemods\' + $Mod.ModFolder)
New-Item -ItemType Directory -Force -Path "$modDir\cfg", "$modDir\materials\console", "$modDir\addons" | Out-Null
Set-Content -LiteralPath "$modDir\gameinfo.txt" -Value '"GameInfo" { game "test" }'
# server.cfg with LF line endings (StargateTC 2 ships it so), the others CRLF.
[IO.File]::WriteAllText("$modDir\cfg\server.cfg", "hostname `"test`"`nsv_lan 0`n")
[IO.File]::WriteAllText("$modDir\cfg\listenserver.cfg", "exec server.cfg`r`n")
[IO.File]::WriteAllText("$modDir\materials\console\background01.vtf", 'original splash')
$args1 = @('-ModDir', $modDir)
$sdk = $null
if ($Mod.SdkBaseFolder) {
    $sdk = Join-Path $root ('Steam\steamapps\common\' + $Mod.SdkBaseFolder)
    New-Item -ItemType Directory -Force -Path "$sdk\bin", "$sdk\platform\config" | Out-Null
    [IO.File]::WriteAllText("$sdk\bin\engine.dll", 'original engine')
    [IO.File]::WriteAllText("$sdk\bin\ServerBrowser.dll", 'original browser')
    [IO.File]::WriteAllText("$sdk\platform\config\masterservers.vdf", "`"MasterServers`"`r`n{`r`n}`r`n")
    $args1 += @('-SdkBaseDir', $sdk)
}
$before = Snapshot $root
Write-Host "Fake layout: $root ($Shell)"

Write-Host 'install'
Check 'exit code 0' ((Run 'install.ps1' $args1) -eq 0)
if ($script:Fail) { Write-Host $script:LastOutput }
Check 'plugin DLL installed' ((Get-FileHash "$modDir\$($Mod.PluginDll)" -Algorithm MD5).Hash -eq (Get-FileHash (Join-Path $PackageDir "payload\$($Mod.PluginDll)") -Algorithm MD5).Hash)
Check 'waypoints installed' (@(Get-ChildItem "$modDir\addons\botrix\waypoints\*.way").Count -eq @(Get-ChildItem (Join-Path $PackageDir 'payload\addons\botrix\waypoints\*.way')).Count)
$vdf = Get-Content -LiteralPath "$modDir\addons\botrix.vdf" -Raw
if ($Mod.VdfFromSdkBin) {
    Check 'botrix.vdf points from <SDK>\bin to the mod' ($vdf -match ('"file"\s+"\.\./\.\./\.\./sourcemods/' + $Mod.ModFolder + '/addons/botrix"'))
} else {
    Check 'botrix.vdf loads addons/botrix' ($vdf -match '"file"\s+"addons/botrix"')
}
foreach ($cfg in $Mod.CfgFiles) {
    $t = [IO.File]::ReadAllText("$modDir\$cfg")
    Check "$cfg has one bot block" (([regex]::Matches($t, 'Stargate Redial bots \(added')).Count -eq 1 -and $t -match 'botrix config bot quota')
}
Check 'server.cfg keeps LF line endings' (-not ([IO.File]::ReadAllText("$modDir\cfg\server.cfg")).Contains("`r"))
if (Test-Path (Join-Path $PackageDir 'payload\materials')) {
    Check 'splash replaced, original backed up' ((Get-Content "$modDir\redial-backup\materials\console\background01.vtf" -Raw) -eq 'original splash')
}
if ($Mod.ServerBrowserFix) {
    foreach ($k in $Mod.ServerBrowserFixFiles.Keys) {
        Check "browser fix: $k" ((Get-FileHash "$sdk\$k" -Algorithm MD5).Hash -eq $Mod.ServerBrowserFixFiles[$k])
    }
    Check 'browser fix: original engine backed up' ((Get-Content "$sdk\redial-backup\bin\engine.dll" -Raw) -eq 'original engine')
}

Write-Host 'install again'
$mid = Snapshot $root
Check 'exit code 0' ((Run 'install.ps1' $args1) -eq 0)
Check 'nothing changed' (Same-Snapshot $mid (Snapshot $root))

Write-Host 'uninstall'
Check 'exit code 0' ((Run 'uninstall.ps1' $args1) -eq 0)
$after = Snapshot $root
Check 'every original file back, nothing left' (Same-Snapshot $before $after)
if (-not (Same-Snapshot $before $after)) {
    foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { Write-Host "    left: $k" } elseif ($before[$k] -ne $after[$k]) { Write-Host "    differs: $k" } }
    foreach ($k in $before.Keys) { if (-not $after.ContainsKey($k)) { Write-Host "    missing: $k" } }
}
Check 'no empty folder left (addons\botrix)' (-not (Test-Path "$modDir\addons\botrix"))

Write-Host 'uninstall again'
Check 'exit code 0' ((Run 'uninstall.ps1' $args1) -eq 0)

Write-Host 'package without the plugin DLL (source download)'
$pkg2 = Join-Path $root 'pkg-nodll'
Copy-Item -LiteralPath $PackageDir -Destination $pkg2 -Recurse
Remove-Item -LiteralPath (Join-Path $pkg2 "payload\$($Mod.PluginDll)")
$rc = Run 'install.ps1' $args1 $pkg2
Check 'refused with a clear message' ($rc -ne 0 -and $script:LastOutput -match 'Releases page')
Check 'mod untouched' (Same-Snapshot $before (Snapshot $root | ForEach-Object { $s = $_; $r = @{}; foreach ($k in $s.Keys) { if (-not $k.StartsWith('\pkg-nodll')) { $r[$k] = $s[$k] } }; $r }))

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed"
exit [int]($script:Fail -gt 0)
