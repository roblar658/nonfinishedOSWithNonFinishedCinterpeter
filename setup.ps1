# ==============================================================================
# CustomC-OS: Installasjon og Oppstart av Terminal & MSB
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   CustomC-OS: Oppsett av Terminal-Operativsystem         " -ForegroundColor Cyan
Write-Host "   MSB (Master Boot Sector) & Kjerne-Terminal             " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# 1. Bygg OS-et
& "$scriptDir\build.ps1"

# 2. Fjern eventuelle gamle web-containere
$oldContainer = docker ps -a -q -f name=^custom-cos$
if ($oldContainer) {
    Write-Host "[*] Fjerner gammel web-container..." -ForegroundColor DarkGray
    docker rm -f custom-cos | Out-Null
}

Write-Host "`n[+] Installasjon og bygging fullført!" -ForegroundColor Green
Write-Host "[*] Starter CustomC-OS terminalen nå..." -ForegroundColor Yellow
Start-Sleep -Seconds 1

# 3. Start terminalen
& "$scriptDir\run.ps1"
