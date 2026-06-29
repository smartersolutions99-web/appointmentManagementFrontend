# ============================================================================
#  build_installer.ps1
#  Jedna komanda: napravi desktop build + ubaci runtime + napravi instaler.
#
#  Pokretanje (iz korijena projekta):
#      powershell -ExecutionPolicy Bypass -File .\build_installer.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$release = ".\build\windows\x64\runner\Release"

Write-Host "==> 1/3  Flutter release build..." -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Host "Build nije uspio." -ForegroundColor Red; exit 1 }

Write-Host "==> 2/3  Kopiram Visual C++ runtime DLL-ove..." -ForegroundColor Cyan
$dlls = "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"
foreach ($d in $dlls) {
    Copy-Item (Join-Path $env:WINDIR "System32\$d") $release -Force
}

Write-Host "==> 3/3  Pravim instaler (Inno Setup)..." -ForegroundColor Cyan
# Pronađi ISCC.exe (Inno Setup command-line compiler) na uobičajenim lokacijama.
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Host "ISCC.exe nije pronadjen. Otvori installer.iss u Inno Setup-u i pritisni F9." -ForegroundColor Yellow
    exit 0
}

& $iscc ".\installer.iss"
if ($LASTEXITCODE -ne 0) { Write-Host "Pravljenje instalera nije uspjelo." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "GOTOVO! Instaler je u: installer_output\SalonMenadzment-Setup.exe" -ForegroundColor Green
