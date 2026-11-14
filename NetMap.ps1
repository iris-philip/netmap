<#
Run from VS Code's PowerShell terminal:
  .\NetMap.ps1 run
  .\NetMap.ps1 apk
  .\NetMap.ps1 both
Optionally select an Android virtual device: -Avd 'Your_AVD_Name'
Pass -Signer to sign an APK with a private signing setup stored outside this repository.
#>
[CmdletBinding()]
param(
    [ValidateSet('run', 'apk', 'both')][string]$Action = 'run',
    [string]$Avd,
    [string]$FlutterRoot = $env:FLUTTER_ROOT,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$Signer,
    [string]$OutputApk
)
$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
. "$PSScriptRoot\environment.ps1" -FlutterRoot $FlutterRoot
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
if (-not $AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk with the Android SDK path.' }
if (-not $JavaHome) { throw 'Set JAVA_HOME or pass -JavaHome with the Java installation path.' }
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'
$apkSigner = Join-Path $AndroidSdk 'build-tools\36.0.0\apksigner.bat'

function Invoke-Flutter {
    & $flutter @args
    if ($LASTEXITCODE -ne 0) { throw "Flutter failed (exit $LASTEXITCODE)." }
}

foreach ($required in @($flutter, (Join-Path $project 'pubspec.yaml'), (Join-Path $JavaHome 'bin\java.exe'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing required file: $required" }
}
if ($Action -ne 'run' -and $Signer) {
    foreach ($required in @($Signer, (Join-Path (Split-Path $Signer) 'netmap-release.p12'), (Join-Path (Split-Path $Signer) 'keystore-password.txt'), $apkSigner)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing signing file: $required" }
    }
}

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk

Push-Location $project
try {
    Invoke-Flutter pub get
    if ($Action -ne 'apk') {
        foreach ($required in @($adb, $emulator)) {
            if (-not (Test-Path -LiteralPath $required)) { throw "Missing Android tool: $required" }
        }
        & $adb start-server
        if ($LASTEXITCODE -ne 0) { throw 'Unable to start Android Debug Bridge.' }
        $serial = $null
        foreach ($line in (& $adb devices)) {
            if ($line -match '^(emulator-\d+)\s+device$') {
                $candidate = $Matches[1]
                $runningAvd = @(& $adb -s $candidate emu avd name)[0]
                if (-not $Avd -or $runningAvd -eq $Avd) { $serial = $candidate; break }
            }
        }
        if (-not $serial) {
            $available = @(& $emulator -list-avds | Where-Object { $_.Trim() })
            if ($available.Count -eq 0) { throw 'No emulator exists. Create one in Android Studio > Device Manager.' }
            if (-not $Avd) { $Avd = $available[0].Trim() }
            if ($Avd -notin $available) { throw "Unknown AVD '$Avd'. Available: $($available -join ', ')" }
            Write-Host "Starting emulator: $Avd"
            Start-Process -FilePath $emulator -ArgumentList @('-avd', $Avd) -WindowStyle Hidden | Out-Null
        }
        $deadline = (Get-Date).AddMinutes(5)
        $ready = $false
        do {
            foreach ($line in (& $adb devices)) {
                if ($line -match '^(emulator-\d+)\s+device$') {
                    $candidate = $Matches[1]
                    $runningAvd = @(& $adb -s $candidate emu avd name)[0]
                    if ($Avd -and $runningAvd -ne $Avd) { continue }
                    if ((& $adb -s $candidate shell getprop sys.boot_completed) -match '^1') {
                        $serial = $candidate
                        $ready = $true
                        break
                    }
                }
            }
            if (-not $ready) { Start-Sleep -Seconds 3 }
        } until ($ready -or (Get-Date) -gt $deadline)
        if (-not $ready) { throw 'Emulator did not finish booting within five minutes.' }
        Write-Host 'Launching NetMap. Press r to hot reload; q to stop.'
        Invoke-Flutter run -d $serial
    }
    if ($Action -ne 'run') {
        Invoke-Flutter build apk --release
        $unsignedApk = Join-Path $project 'build\app\outputs\flutter-apk\app-release.apk'
        if ($Signer) {
            if (-not $OutputApk) { $OutputApk = Join-Path $project 'dist\NetMap-Iris-signed.apk' }
            $outputDirectory = Split-Path -Parent $OutputApk
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
            & $Signer -InputApk $unsignedApk -OutputApk $OutputApk -JavaHome $JavaHome -ApkSigner $apkSigner
            if ($LASTEXITCODE -ne 0) { throw 'APK signing failed.' }
            Write-Host "Signed APK: $OutputApk" -ForegroundColor Green
        } else {
            Write-Host "Unsigned APK: $unsignedApk" -ForegroundColor Green
        }
    }
}
finally { Pop-Location }
