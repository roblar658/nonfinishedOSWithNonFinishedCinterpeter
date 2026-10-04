# Stop script for CustomC-OS
Write-Host "[*] Stopper CustomC-OS container..." -ForegroundColor Yellow
docker stop custom-cos | Out-Null
Write-Host "[+] CustomC-OS er stoppet." -ForegroundColor Green
