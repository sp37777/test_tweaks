@echo off
setlocal enabledelayedexpansion

:: 1. Clear existing layout registry key to remove duplications 
reg delete "HKCU\Keyboard Layout\Preload" /f
reg add "HKCU\Keyboard Layout\Preload" /f

:: 2. Add layouts fresh (1 = primary, 2 = secondary) 
:: 00000409 is US English, 00000422 is Ukrainian
reg add "HKCU\Keyboard Layout\Preload" /v 1 /t REG_SZ /d 00000409 /f
reg add "HKCU\Keyboard Layout\Preload" /v 2 /t REG_SZ /d 00000422 /f

:: 3. Apply the layout to the current session 
wpeutil SetKeyboardLayout 0409:00000409

:: 4. Detect Paths
set "SCRIPT_DIR=%~dp0"
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set "ARCH=64") else (set "ARCH=86")
set "APP_PATH=%SCRIPT_DIR%tweak_chooser_x%ARCH%.exe"

:: 5. Launch
if not exist "%APP_PATH%" (
    echo ERROR: App not found at %APP_PATH%
    pause
    exit /b 1
)

:: a stale result from a previous run must never be applied
del /q "%SCRIPT_DIR%user_choices.json" "%SCRIPT_DIR%user_choices.json.tmp" 2>nul

:: default template, unless the caller passed its own parameters
set "APP_ARGS=%*"
if not defined APP_ARGS set "APP_ARGS=-c "%SCRIPT_DIR%10_choices.json""

echo Launching with params: %APP_ARGS%
start "" /wait "%APP_PATH%" %APP_ARGS%
echo tweak_chooser exit code: %errorlevel%