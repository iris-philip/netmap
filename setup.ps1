param([switch]$WindowsTools)
$ErrorActionPreference = 'Stop'
if ($WindowsTools) { & "$PSScriptRoot\Install-WindowsBuildTools.ps1" }
. "$PSScriptRoot\environment.ps1"
Push-Location $PSScriptRoot
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency setup failed.' }
    & $flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
    & $flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    Write-Host 'Project checks passed. Use .\run.ps1 android or .\build.ps1 android (or windows).'
} finally { Pop-Location }
