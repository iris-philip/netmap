param([ValidateSet('android','windows','all')][string]$Target = 'android')
$ErrorActionPreference = 'Stop'
if ($Target -in @('android','all')) { & "$PSScriptRoot\NetMap.ps1" apk }
if ($Target -in @('windows','all')) { & "$PSScriptRoot\Build-Windows.ps1" }
