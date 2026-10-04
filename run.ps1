# ==============================================================================
# CustomC-OS: Oppstartsskript for Terminalen
# ==============================================================================
param (
    [switch]$Console,
    [switch]$Docker
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$imgPath = Join-Path $scriptDir "custom_c_os.img"
if (-not (Test-Path $imgPath)) {
    Write-Host "[*] custom_c_os.img ikke funnet. Kjører byggeskript først..." -ForegroundColor Yellow
    & "$scriptDir\build.ps1"
}

# Sjekk native QEMU
$qemuExe = $null
$qemuLocations = @(
    "qemu-system-x86_64",
    "qemu-system-i386",
    "C:\Program Files\qemu\qemu-system-x86_64.exe",
    "C:\Program Files\qemu\qemu-system-i386.exe",
    "C:\Program Files (x86)\qemu\qemu-system-i386.exe"
)

foreach ($loc in $qemuLocations) {
    if (Get-Command $loc -ErrorAction SilentlyContinue) {
        $qemuExe = $loc
        break
    } elseif (Test-Path $loc) {
        $qemuExe = $loc
        break
    }
}

if ($qemuExe -and (-not $Docker)) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Starter CustomC-OS Terminal (Native QEMU)              " -ForegroundColor Cyan
    Write-Host "   Bootloader: MSB (Master Boot Sector)                   " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    if ($Console) {
        Write-Host "[*] Kjører i gjeldende terminalkonsoll..." -ForegroundColor Yellow
        & $qemuExe -drive "format=raw,file=$imgPath" -boot a -nographic -monitor none
    } else {
        Write-Host "[*] Åpner CustomC-OS terminalvindu..." -ForegroundColor Green
        Start-Process $qemuExe -ArgumentList "-drive format=raw,file=`"$imgPath`" -boot a -rtc base=localtime"
    }
} else {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Starter CustomC-OS Terminal (via Docker)               " -ForegroundColor Cyan
    Write-Host "   Bootloader: MSB (Master Boot Sector)                   " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    # Kjør containeren i interaktiv tty-modus direkte i gjeldende konsoll
    docker run -it --rm -v "${scriptDir}:/env" dev-real-dos qemu-system-i386 -fda /env/custom_c_os.img -boot a -nographic -monitor none
}
