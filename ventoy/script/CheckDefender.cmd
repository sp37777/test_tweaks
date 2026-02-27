@echo off
setlocal enabledelayedexpansion

:: 1. Пошук флешки (за наявністю INI файлу)
set "USB="
for %%i in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%i:\ventoy\script\user_choices.ini" set "USB=%%i:"
)

if not defined USB exit /b [cite: 9]

set "INI=%USB%\ventoy\script\user_choices.ini"
set "DISABLE_DEF=false"

:: 2. Читання INI без зовнішніх утиліт [cite: 12]
for /f "usebackq tokens=1,2 delims==" %%a in ("%INI%") do (
    set "key=%%a"
    set "val=%%b"
    :: Очищення від пробілів
    set "key=!key: =!"
    set "val=!val: =!"
    
    if /i "!key!"=="DisableDefender" if /i "!val!"=="true" set "DISABLE_DEF=true"
)

:: 3. Запуск VBS
if "!DISABLE_DEF!"=="true" (
    if exist "X:\defender.vbs" (
        echo [%TIME%] Launching Defender killer like original... >> X:\defender_winpe.log
        :: Використовуємо саме cscript і параметри як у schneegans
        start /MIN cscript.exe //E:vbscript "X:\defender.vbs"
    )
)
exit /b