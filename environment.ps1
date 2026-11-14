param([string]$FlutterRoot = $env:FLUTTER_ROOT)
$ErrorActionPreference = 'Stop'

if ($FlutterRoot) {
    $flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter SDK not found: $FlutterRoot" }
} else {
    $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if (-not $flutterCommand) { $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue }
    if (-not $flutterCommand) { throw 'Flutter was not found. Add it to PATH or set FLUTTER_ROOT.' }
    $flutter = $flutterCommand.Source
    if (-not $flutter) { $flutter = $flutterCommand.Definition }
    $FlutterRoot = Split-Path -Parent (Split-Path -Parent $flutter)
}

$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $FlutterRoot.Replace('\', '/')
