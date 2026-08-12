# ============================================================================
#  release.ps1  -  Napravi i objavi novu verziju (Android + Windows) jednom komandom.
#
#  STA RADI:
#   1. Podigne verziju u pubspec.yaml i installer\salon.iss
#   2. Napravi Android APK
#   3. Napravi Windows aplikaciju + instaler (Inno Setup)
#   4. Kopira oba fajla u lokalni releases repo
#   5. Napravi version.json (obavezna ili opciona nadogradnja)
#   6. Posalje sve na GitHub  ->  korisnici dobijaju prompt pri sljedecoj prijavi
#
#  KAKO SE POKRECE (iz foldera projekta):
#     .\release.ps1 -Version "1.2.0" -Notes "Kratak opis sta je novo."
#
#  OBAVEZNA nadogradnja (korisnik MORA da azurira, nema dugme Kasnije):
#     .\release.ps1 -Version "1.2.0" -Notes "Vazna ispravka." -Mandatory
#
#  NAPOMENA: u -Notes NE koristi znak navodnika (") - pokvari version.json.
# ============================================================================
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Notes = "Nova verzija.",
  [switch]$Mandatory,
  [string]$ReleasesRepo = "C:\Users\djuro\SalonReleases\AppointmentManagementApps"
)

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$base = "https://raw.githubusercontent.com/smartersolutions99-web/AppointmentManagementApps/main"

# Pise tekst kao UTF-8 BEZ BOM-a (bitno: sa BOM-om aplikacija ne moze da procita version.json).
function Write-Utf8NoBom($path, $text) {
  $full = [System.IO.Path]::GetFullPath($path)
  [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# --- Provjere prije pocetka ---
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Verzija mora biti oblika X.Y.Z (npr. 1.2.0)." }
if (-not (Test-Path $iscc)) { throw "Ne nalazim Inno Setup: $iscc" }
if (-not (Test-Path $ReleasesRepo)) { throw "Ne nalazim releases repo: $ReleasesRepo  (kloniraj ga prvo)." }

# --- 1. Podigni verziju u pubspec.yaml (i uvecaj build broj) ---
$pub = Get-Content "pubspec.yaml" -Raw -Encoding UTF8
if ($pub -notmatch 'version:\s*\d+\.\d+\.\d+\+(\d+)') { throw "Ne mogu da procitam verziju iz pubspec.yaml." }
$newBuild = [int]$Matches[1] + 1
$pub = $pub -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $Version+$newBuild"
Write-Utf8NoBom "pubspec.yaml" $pub
Write-Host "1/8  pubspec.yaml  ->  $Version+$newBuild" -ForegroundColor Cyan

# --- 2. Podigni verziju u installer\salon.iss ---
$iss = Get-Content "installer\salon.iss" -Raw -Encoding UTF8
$iss = $iss -replace '#define MyAppVersion "\d+\.\d+\.\d+"', "#define MyAppVersion `"$Version`""
Write-Utf8NoBom "installer\salon.iss" $iss
Write-Host "2/8  salon.iss  ->  $Version" -ForegroundColor Cyan

# --- 3. Android APK ---
Write-Host "3/8  Gradim Android APK (moze potrajati par minuta)..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "APK build nije uspio." }

# --- 4. Windows aplikacija ---
Write-Host "4/8  Gradim Windows aplikaciju..." -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Windows build nije uspio." }

# --- 5. Windows instaler (Inno Setup) ---
Write-Host "5/8  Pravim Windows instaler..." -ForegroundColor Cyan
& $iscc "installer\salon.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup nije uspio." }

# --- 6. Kopiraj fajlove u releases repo ---
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$ReleasesRepo\apk\salon-$Version.apk" -Force -ErrorAction Stop
Copy-Item "installer\Output\salon-setup-$Version.exe" "$ReleasesRepo\windows\salon-setup-$Version.exe" -Force -ErrorAction Stop
Write-Host "6/8  Fajlovi kopirani u repo." -ForegroundColor Cyan

# --- 7. Napravi version.json ---
if ($Mandatory) { $minVersion = $Version } else { $minVersion = "1.0.0" }
$json = @"
{
  "android": {
    "latestVersion": "$Version",
    "minVersion": "$minVersion",
    "url": "$base/apk/salon-$Version.apk"
  },
  "windows": {
    "latestVersion": "$Version",
    "minVersion": "$minVersion",
    "url": "$base/windows/salon-setup-$Version.exe"
  },
  "notes": "$Notes"
}
"@
Write-Utf8NoBom "$ReleasesRepo\version.json" $json
Write-Host "7/8  version.json napravljen (obavezna nadogradnja = $($Mandatory.IsPresent))." -ForegroundColor Cyan

# --- 8. Posalji na GitHub ---
Write-Host "8/8  Saljem na GitHub..." -ForegroundColor Cyan
Push-Location $ReleasesRepo
git add -A
git commit -m "Verzija $Version"
git push origin main
$pushOk = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $pushOk) { throw "git push nije uspio - provjeri internet / pristup repou." }

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host " GOTOVO! Verzija $Version je objavljena." -ForegroundColor Green
Write-Host " Korisnici dobijaju prompt za nadogradnju pri sljedecoj prijavi." -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "NE ZABORAVI: commit-uj i glavni projekat (pubspec.yaml i salon.iss su izmijenjeni)." -ForegroundColor Yellow
