param([string]$FlutterRoot = $env:FLUTTER_ROOT)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\environment.ps1" -FlutterRoot $FlutterRoot

Push-Location $PSScriptRoot
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    & $flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
    & $flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    & $flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    $release = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'
    $dist = Join-Path $PSScriptRoot 'dist'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    $zip = Join-Path $dist 'NetMap-Windows.zip'
    Compress-Archive -Path "$release\*" -DestinationPath $zip -Force
    Write-Host "Windows bundle: $zip"
    Write-Host "Executable: $release\netmap.exe"
} finally { Pop-Location }
