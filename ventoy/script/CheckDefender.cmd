@echo off
setlocal enabledelayedexpansion

:: 1. Search the usb drive (by existing of the INI file)
set "USB="
for %%i in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%i:\ventoy\script\user_choices.ini" set "USB=%%i:"
)

if not defined USB exit /b [cite: 9]

set "INI=%USB%\ventoy\script\user_choices.ini"
set "DISABLE_DEF=false"

:: 2. Read INI [cite: 12]
for /f "usebackq tokens=1,2 delims==" %%a in ("%INI%") do (
    set "key=%%a"
    set "val=%%b"
    :: Space trim
    set "key=!key: =!"
    set "val=!val: =!"
    
    if /i "!key!"=="DisableDefender" if /i "!val!"=="1" set "DISABLE_DEF=true"
)

:: 3. Launch VBS
if "!DISABLE_DEF!"=="true" (
    if exist "X:\defender.vbs" (
        echo [%TIME%] Launching Defender killer like original... >> X:\defender_winpe.log
        :: Use the cscript with schneegans params
        start /MIN cscript.exe //E:vbscript "X:\defender.vbs"
    )
)
exit /b