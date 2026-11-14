@echo off
setlocal
set "APPDIR=%~dp0build\windows\x64\runner\Release"
if not exist "%APPDIR%\netmap.exe" (
    echo NetMap has not been built yet. Building now...
    call "%~dp0Build-Windows.cmd"
    if errorlevel 1 (
        echo Build failed. See the error above.
        pause
        exit /b 1
    )
)
if not exist "%APPDIR%\netmap.exe" (
    echo Cannot find NetMap in "%APPDIR%".
    pause
    exit /b 1
)
start "" /D "%APPDIR%" "%APPDIR%\netmap.exe"
exit /b 0
