param([switch]$Rebuild, [string]$Compiler)
$ErrorActionPreference = 'Stop'
if ($Rebuild -or -not (Test-Path "$PSScriptRoot\build\windows\x64\runner\Release\netmap.exe")) {
    & "$PSScriptRoot\Build-Windows.ps1"
}
if (-not $Compiler) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
    )
    $Compiler = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) {
    throw 'Install Inno Setup from https://jrsoftware.org/isdl.php then rerun this script, or pass -Compiler with the full ISCC.exe path.'
}
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$redist = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory | Sort-Object Name -Descending | ForEach-Object {
    Join-Path $_.FullName 'x64\Microsoft.VC143.CRT'
} | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $redist) { throw 'Visual C++ redistributable DLLs are missing from Build Tools.' }
$runtime = Join-Path $PSScriptRoot 'installer\runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
Copy-Item "$redist\*.dll" $runtime -Force
$versionMatch = [regex]::Match((Get-Content "$PSScriptRoot\pubspec.yaml" -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)')
if (-not $versionMatch.Success) { throw 'Cannot determine app version.' }
& $Compiler ('/DAppVersion=' + $versionMatch.Groups[1].Value) "$PSScriptRoot\installer\NetMap.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Write-Host "Installer: $PSScriptRoot\dist\NetMap-$($versionMatch.Groups[1].Value)-Windows-Setup.exe"
