# ==============================================================================
# CustomC-OS: Byggeskript for MSB Bootloader, Kjerne og Disk-image
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  CustomC-OS: Bygger MSB Bootloader og Operativsystem     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Finn NASM
$nasmCmd = "nasm"
if (Get-Command nasm -ErrorAction SilentlyContinue) {
    $nasmCmd = "nasm"
} elseif (Test-Path "C:\mingw64\bin\nasm.exe") {
    $nasmCmd = "C:\mingw64\bin\nasm.exe"
} else {
    Write-Host "[!] nasm ble ikke funnet i PATH eller C:\mingw64\bin." -ForegroundColor Yellow
}

# 1. Bygg Master Boot Sector (MSB / MBR)
Write-Host "[1/3] Kompilerer MSB (Master Boot Sector)..." -ForegroundColor Yellow
& $nasmCmd -f bin "$scriptDir\boot\msb_boot.asm" -o "$scriptDir\boot\msb_boot.bin"
$msbSize = (Get-Item "$scriptDir\boot\msb_boot.bin").Length
if ($msbSize -ne 512) {
    Write-Error "[!] Feil: MSB må være nøyaktig 512 bytes! Faktisk størrelse: $msbSize bytes."
    exit 1
}
Write-Host "      [OK] MSB kompilert ($msbSize bytes med 0xAA55 signatur)" -ForegroundColor Green

# 2. Bygg OS-kjerne
Write-Host "[2/3] Kompilerer CustomC-OS Kjerne & Terminal..." -ForegroundColor Yellow
& $nasmCmd -f bin -I "$scriptDir\kernel\" "$scriptDir\kernel\kernel.asm" -o "$scriptDir\kernel\kernel.bin"
$kernelSize = (Get-Item "$scriptDir\kernel\kernel.bin").Length
Write-Host "      [OK] Kjerne kompilert ($kernelSize bytes)" -ForegroundColor Green

# 3. Bygg bootbart 1.44MB disk-image (custom_c_os.img)
Write-Host "[3/3] Pakker bootbar disk-image (custom_c_os.img)..." -ForegroundColor Yellow
$bootBytes = [System.IO.File]::ReadAllBytes("$scriptDir\boot\msb_boot.bin")
$kernelBytes = [System.IO.File]::ReadAllBytes("$scriptDir\kernel\kernel.bin")

# 1.44MB Floppy / HDD Raw Image = 1,474,560 bytes
$imgBytes = New-Object byte[] 1474560
[System.Array]::Copy($bootBytes, 0, $imgBytes, 0, $bootBytes.Length)
[System.Array]::Copy($kernelBytes, 0, $imgBytes, 512, $kernelBytes.Length)

$imgPath = "$scriptDir\custom_c_os.img"
try {
    [System.IO.File]::WriteAllBytes($imgPath, $imgBytes)
} catch [System.IO.IOException] {
    Write-Host "[!] $imgPath er i bruk av en kjorende emulator/container (QEMU/Docker)." -ForegroundColor Yellow
    Write-Host "    Stopper kjorende instanser for aa frigi filen..." -ForegroundColor Yellow

    # Stopp lokale qemu-prosesser hvis de kjorer
    Get-Process *qemu* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Stopp docker-containere som bruker dev-real-dos
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $cIds = docker ps -q --filter ancestor=dev-real-dos 2>$null
        if ($cIds) {
            docker stop $cIds 2>$null | Out-Null
        }
    }

    Start-Sleep -Milliseconds 600
    try {
        [System.IO.File]::WriteAllBytes($imgPath, $imgBytes)
    } catch {
        Write-Error "[!] Feil: Kunne ikke skrive til $imgPath fordi den er last. Lukk QEMU/Docker og prov igjen."
        exit 1
    }
}

$imgSize = (Get-Item "$scriptDir\custom_c_os.img").Length
Write-Host "      [OK] $scriptDir\custom_c_os.img generert ($imgSize bytes)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Bygging fullført! Kjør .\run.ps1 for å starte terminalen  " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
