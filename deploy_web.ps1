# =============================================================================
#  deploy_web.ps1  —  ALTERNATIVA Git deploy-u (ručni deploy preko Vercel CLI)
# =============================================================================
#  Glavni način je Git integracija (push -> Vercel sam buduje, vidi vercel.json).
#  Ova skripta je za slučaj da hoćeš da deployuješ RUČNO bez pushovanja:
#  build-uje web lokalno i šalje gotove fajlove na Vercel.
#
#  --- Uradi JEDNOM ---
#    1) npm i -g vercel          (treba ti Node.js: https://nodejs.org)
#    2) vercel login
#
#  --- Pokretanje ---
#    ./deploy_web.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

if (-not (Get-Command vercel -ErrorAction SilentlyContinue)) {
    Write-Host "Vercel CLI nije pronađen." -ForegroundColor Red
    Write-Host "Instaliraj ga sa:  npm i -g vercel   (pa: vercel login)" -ForegroundColor Yellow
    exit 1
}

Write-Host "==> 1/3  Buildujem Flutter web (release)..." -ForegroundColor Cyan
flutter build web --release

# Ručni deploy šalje već izbuildovan build/web, pa mu treba config SAMO sa
# proksijem (bez build-komandi iz root vercel.json-a).
Write-Host "==> 2/3  Pravim vercel.json (proxy /api -> Railway) u build/web..." -ForegroundColor Cyan
$proxyConfig = @'
{
  "rewrites": [
    {
      "source": "/api/:path*",
      "destination": "https://appointmentmanagement-production-543b.up.railway.app/api/:path*"
    },
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ]
}
'@
Set-Content -Path "build/web/vercel.json" -Value $proxyConfig -Encoding utf8

Write-Host "==> 3/3  Deploy na Vercel (produkcija)..." -ForegroundColor Cyan
vercel deploy "build/web" --prod

Write-Host ""
Write-Host "Gotovo! Vercel je gore ispisao URL na kojem je aplikacija." -ForegroundColor Green
