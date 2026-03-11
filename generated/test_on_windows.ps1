# Run this on Windows VM to test HTTP connectivity
Write-Host "=== Testing HTTP Connection ===" -ForegroundColor Cyan
Write-Host ""

$url = "http://localhost:8000/generated/payloads/stage2.ps1"
Write-Host "Testing URL: $url" -ForegroundColor Yellow

try {
    $wc = New-Object System.Net.WebClient
    $content = $wc.DownloadString($url)
    Write-Host "[✓] SUCCESS! Downloaded $($content.Length) bytes" -ForegroundColor Green
    Write-Host ""
    Write-Host "First 100 characters:"
    Write-Host $content.Substring(0, [Math]::Min(100, $content.Length))
} catch {
    Write-Host "[✗] FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
