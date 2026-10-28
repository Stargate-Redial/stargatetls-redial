<#
.SYNOPSIS
    Removes what install.ps1 installed and puts the original files back.

.PARAMETER ModDir
    The mod's folder, if it isn't found.

.PARAMETER SdkBaseDir
    The Source SDK Base folder, if it isn't found (StargateTC 2 only).

.PARAMETER KeepServerBrowserFix
    StargateTC 2: leave the server browser fix in Source SDK Base.
#>
param(
    [string]$ModDir,
    [string]$SdkBaseDir,
    [switch]$KeepServerBrowserFix
)

. (Join-Path $PSScriptRoot 'redial-common.ps1')
$Mod = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'mod.psd1')

Write-Host "$($Mod.Title) uninstaller"
Write-Host ''

$steam = Get-SteamDir
if (-not $ModDir) {
    $sm = Get-SourceModsDir $steam
    if ($sm) { $ModDir = Join-Path $sm $Mod.ModFolder }
}
if (-not $ModDir -or -not (Test-Path -LiteralPath $ModDir)) {
    Stop-Redial "$($Mod.ModName) not found. Pass -ModDir ""<path>\steamapps\sourcemods\$($Mod.ModFolder)""."
}
$ModDir = [IO.Path]::GetFullPath($ModDir).TrimEnd('\')

$sdk = $null
if ($Mod.ServerBrowserFix -and -not $KeepServerBrowserFix) {
    $sdk = $SdkBaseDir
    if (-not $sdk) { $sdk = Find-SdkBase $steam $Mod.SdkBaseFolder }
    if ($sdk) { $sdk = [IO.Path]::GetFullPath($sdk).TrimEnd('\') }
}
$running = Get-RunningGame $ModDir $sdk
if ($running) {
    Stop-Redial "The game is running ($($running.ExecutablePath), process $($running.ProcessId)). Close it, then run the uninstaller again."
}

if (Test-Path -LiteralPath (Join-Path $ModDir "$BackupFolder\$ManifestName")) {
    $n = Uninstall-Files $ModDir
    # cfg files that existed before: only our block goes.
    foreach ($cfg in $Mod.CfgFiles) { Remove-CfgBlock (Join-Path $ModDir $cfg) | Out-Null }
    Write-Step "Bots removed from $ModDir ($n files restored or removed)."
} else {
    Write-Step "No Redial bots installed in $ModDir."
}

if ($Mod.ServerBrowserFix) {
    if ($KeepServerBrowserFix) {
        Write-Step 'Server browser fix: kept (-KeepServerBrowserFix).'
    } elseif ($sdk -and (Test-Path -LiteralPath (Join-Path $sdk "$BackupFolder\$ManifestName"))) {
        $n = Uninstall-Files $sdk
        Write-Step "Server browser fix removed from $sdk ($n files restored or removed)."
    } else {
        Write-Step 'Server browser fix: not installed by Redial.'
    }
}

Write-Host ''
Write-Host 'Done.'
exit 0
