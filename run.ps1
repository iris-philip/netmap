param([ValidateSet('android','windows')][string]$Target = 'android', [string]$Avd)
$ErrorActionPreference = 'Stop'
if ($Target -eq 'android') {
    & "$PSScriptRoot\NetMap.ps1" run -Avd $Avd
} else {
    . "$PSScriptRoot\environment.ps1"
    Push-Location $PSScriptRoot
    try {
        & $flutter run -d windows
        if ($LASTEXITCODE -ne 0) { throw 'Windows launch failed.' }
    } finally { Pop-Location }
}
