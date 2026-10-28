# Shared by install.ps1 and uninstall.ps1 (Stargate Redial, Source mods). Windows PowerShell 5.1 and PowerShell 7.
# Keep this file ASCII: Windows PowerShell reads BOM-less scripts in the ANSI code page.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$BackupFolder = 'redial-backup'
$ManifestName = 'installed.txt'
$CfgBegin = '// >>> Stargate Redial bots (added by install.bat; uninstall.bat removes this block)'
$CfgEnd = '// <<< Stargate Redial bots'
$Latin1 = [Text.Encoding]::GetEncoding(28591)

function Write-Step([string]$Text) { Write-Host "* $Text" }
function Write-Note([string]$Text) { Write-Host "  $Text" }
function Stop-Redial([string]$Text) { throw $Text }

function Get-Md5([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash }

function Test-SameFile([string]$A, [string]$B) {
    if (-not (Test-Path -LiteralPath $A -PathType Leaf) -or -not (Test-Path -LiteralPath $B -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $A).Length -ne (Get-Item -LiteralPath $B).Length) { return $false }
    return (Get-Md5 $A) -eq (Get-Md5 $B)
}

# Steam folder and its libraries (steamapps\libraryfolders.vdf).
function Get-SteamDir {
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($p) {
            foreach ($name in 'SteamPath', 'InstallPath') {
                if ($p.PSObject.Properties[$name] -and (Test-Path -LiteralPath $p.$name)) {
                    return [IO.Path]::GetFullPath(($p.$name -replace '/', '\'))
                }
            }
        }
    }
    return $null
}

function Get-SourceModsDir([string]$SteamDir) {
    $p = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($p -and $p.PSObject.Properties['SourceModInstallPath'] -and $p.SourceModInstallPath) {
        return [IO.Path]::GetFullPath(($p.SourceModInstallPath -replace '/', '\'))
    }
    if ($SteamDir) { return (Join-Path $SteamDir 'steamapps\sourcemods') }
    return $null
}

function Get-SteamLibraries([string]$SteamDir) {
    $libs = New-Object System.Collections.Generic.List[string]
    if (-not $SteamDir) { return $libs }
    $libs.Add($SteamDir)
    $vdf = Join-Path $SteamDir 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $lib = $m.Groups[1].Value -replace '\\\\', '\'
            if ((Test-Path -LiteralPath $lib) -and -not ($libs -contains $lib)) { $libs.Add($lib) }
        }
    }
    return $libs
}

function Find-SdkBase([string]$SteamDir, [string]$Folder) {
    foreach ($lib in (Get-SteamLibraries $SteamDir)) {
        $d = Join-Path $lib ('steamapps\common\' + $Folder)
        if (Test-Path -LiteralPath (Join-Path $d 'bin\engine.dll')) { return $d }
    }
    return $null
}

# Relative path from folder $From to $To with forward slashes, or $To itself (forward slashes) on another drive.
function Get-RelativePath([string]$From, [string]$To) {
    $f = [IO.Path]::GetFullPath($From).TrimEnd('\').Split('\')
    $t = [IO.Path]::GetFullPath($To).TrimEnd('\').Split('\')
    if ($f[0] -ne $t[0]) { return ($t -join '/') }
    $i = 0
    while ($i -lt $f.Length -and $i -lt $t.Length -and $f[$i] -eq $t[$i]) { $i++ }
    $parts = @()
    for ($k = $i; $k -lt $f.Length; $k++) { $parts += '..' }
    for ($k = $i; $k -lt $t.Length; $k++) { $parts += $t[$k] }
    return ($parts -join '/')
}

# Running game: hl2.exe with this mod's folder on its command line, or (for a Source SDK Base fix) hl2.exe from
# that folder.
function Get-RunningGame([string]$ModDir, [string]$SdkDir) {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='hl2.exe' OR Name='srcds.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        $cmd = ([string]$p.CommandLine) -replace '/', '\'
        $exe = [string]$p.ExecutablePath
        if ($cmd.IndexOf($ModDir, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $p }
        if ($SdkDir -and $exe -and $exe.StartsWith($SdkDir + '\', [StringComparison]::OrdinalIgnoreCase)) { return $p }
    }
    return $null
}

# Manifest of what was installed under a root folder: "A <path>" added, "R <path>" replaced (original in the
# backup folder), "C <path>" cfg file created by us.
function Read-Manifest([string]$Root) {
    $map = [ordered]@{}
    $m = Join-Path $Root "$BackupFolder\$ManifestName"
    if (Test-Path -LiteralPath $m) {
        foreach ($line in Get-Content -LiteralPath $m) {
            if ($line -match '^([ARC]) (.+)$') { $map[$Matches[2]] = $Matches[1] }
        }
    }
    return $map
}

function Write-Manifest([string]$Root, $Map) {
    $dir = Join-Path $Root $BackupFolder
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lines = @('# Stargate Redial: files installed under ' + $Root + '. A = added, R = replaced (original in this folder), C = cfg created.')
    foreach ($k in $Map.Keys) { $lines += "$($Map[$k]) $k" }
    [IO.File]::WriteAllLines((Join-Path $dir $ManifestName), [string[]]$lines, $Latin1)
}

# Copies $Files (paths relative to $SrcRoot) to $DestRoot. A file that exists and differs is backed up once into
# $DestRoot\redial-backup (the first original is kept across re-runs). Returns counts.
function Install-Files([string]$SrcRoot, [string]$DestRoot, [string[]]$Files) {
    $map = Read-Manifest $DestRoot
    $added = 0; $replaced = 0; $same = 0
    foreach ($rel in $Files) {
        $src = Join-Path $SrcRoot $rel
        $dst = Join-Path $DestRoot $rel
        if (-not $map.Contains($rel)) {
            if (Test-Path -LiteralPath $dst -PathType Leaf) {
                if (Test-SameFile $src $dst) { $same++; continue }
                $bak = Join-Path $DestRoot "$BackupFolder\$rel"
                New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
                Copy-Item -LiteralPath $dst -Destination $bak -Force
                $map[$rel] = 'R'; $replaced++
            } else {
                $map[$rel] = 'A'; $added++
            }
            Write-Manifest $DestRoot $map
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    return @{ Added = $added; Replaced = $replaced; Same = $same }
}

# Undoes Install-Files and the cfg blocks for $DestRoot. Returns the number of files restored or removed.
function Uninstall-Files([string]$DestRoot) {
    $map = Read-Manifest $DestRoot
    $n = 0
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @($map.Keys)) {
        $dst = Join-Path $DestRoot $rel
        switch ($map[$rel]) {
            'R' {
                $bak = Join-Path $DestRoot "$BackupFolder\$rel"
                if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $dst -Force; $n++ }
                else { Write-Note "backup missing, left as is: $rel" }
            }
            'A' {
                if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force; $n++ }
                $dirs.Add((Split-Path $dst))
            }
            'C' {
                if (Test-Path -LiteralPath $dst) {
                    Remove-CfgBlock $dst
                    if (-not ((Get-Content -LiteralPath $dst -Raw) -match '\S')) { Remove-Item -LiteralPath $dst -Force }
                    $n++
                }
            }
        }
    }
    # Folders left empty by removed files, deepest first, never $DestRoot itself.
    $root = [IO.Path]::GetFullPath($DestRoot).TrimEnd('\')
    foreach ($d in ($dirs | Sort-Object -Unique | Sort-Object { $_.Length } -Descending)) {
        $cur = $d
        while ($cur -and $cur.Length -gt $root.Length -and $cur.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            if ((Test-Path -LiteralPath $cur) -and -not (Get-ChildItem -LiteralPath $cur -Force)) { Remove-Item -LiteralPath $cur -Force }
            else { break }
            $cur = Split-Path $cur
        }
    }
    $b = Join-Path $DestRoot $BackupFolder
    if (Test-Path -LiteralPath $b) { Remove-Item -LiteralPath $b -Recurse -Force }
    return $n
}

# cfg block between $CfgBegin and $CfgEnd, written with the file's own line endings. Byte-preserving (Latin-1).
function Remove-CfgBlock([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [IO.File]::ReadAllText($Path, $Latin1)
    $pattern = '(\r?\n)?' + [regex]::Escape($CfgBegin) + '[\s\S]*?' + [regex]::Escape($CfgEnd) + '\r?\n?'
    $new = [regex]::Replace($text, $pattern, '')
    if ($new -ne $text) {
        # Put back the newline that ended the last original line.
        if ($text.Length -gt 0 -and $new.Length -gt 0 -and -not $new.EndsWith("`n")) {
            if ($text -match "`r`n") { $new += "`r`n" } else { $new += "`n" }
        }
        [IO.File]::WriteAllText($Path, $new, $Latin1)
        return $true
    }
    return $false
}

function Set-CfgBlock([string]$Path, [string[]]$Lines) {
    $created = -not (Test-Path -LiteralPath $Path)
    if ($created) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        $text = ''
        $eol = "`r`n"
    } else {
        Remove-CfgBlock $Path | Out-Null
        $text = [IO.File]::ReadAllText($Path, $Latin1)
        if ($text -match "`r`n" -or -not ($text -match "`n")) { $eol = "`r`n" } else { $eol = "`n" }
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $eol }
    }
    $block = $eol + $CfgBegin + $eol + (($Lines | ForEach-Object { $_ }) -join $eol) + $eol + $CfgEnd + $eol
    if ($created) { $block = $block.Substring($eol.Length) }
    [IO.File]::WriteAllText($Path, $text + $block, $Latin1)
    return $created
}
