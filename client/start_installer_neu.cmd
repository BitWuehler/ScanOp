@echo off
REM Dieses Skript startet den PowerShell-Installer mit Administratorrechten
REM und stellt die korrekte Zeichenkodierung (UTF-8) für die Konsole sicher.

:: Prüfen, ob bereits Administratorrechte vorhanden sind
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Fordere Administratorrechte an...
    goto UACPrompt
) else (
    goto gotAdmin
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%~dp0"
    
    REM NEU und WICHTIG: Stellt die Konsole auf UTF-8 um, um Umlaute korrekt darzustellen.
    chcp 65001 > nul
    
    echo Administratorrechte vorhanden. Starte den PowerShell-Installer...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1"
    
    pause
    popd