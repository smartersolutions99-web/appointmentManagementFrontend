# Kako napraviti i objaviti novu verziju

Ovo je uputstvo za izdavanje nove verzije aplikacije (Android + Windows).
Kad objaviš novu verziju, korisnik dobije prompt „Dostupna je nova verzija"
pri sljedećoj prijavi i može da se ažurira jednim klikom.

---

## Kako to radi (ukratko)

- Aplikacija pri prijavi provjeri fajl `version.json` na GitHub-u.
- Ako je verzija u `version.json` **veća** od one koju korisnik ima → prikaže prompt.
- Fajlovi (APK i Windows instaler) i `version.json` stoje u posebnom **javnom**
  repozitorijumu: `smartersolutions99-web/AppointmentManagementApps`.

---

## Priprema (samo JEDNOM — već je urađeno na ovom računaru)

1. Instaliran **Inno Setup** (za Windows instaler): https://jrsoftware.org/isdl.php
2. Kloniran releases repo u:
   `C:\Users\djuro\SalonReleases\AppointmentManagementApps`

> Ako ikad radiš na drugom računaru, ponovi ova dva koraka. Kloniranje:
> ```bash
> git clone https://github.com/smartersolutions99-web/AppointmentManagementApps.git
> ```

---

## ✅ Lak način — jednom komandom (preporuka)

U folderu projekta (`AppointmentManagement`) otvori PowerShell i pokreni:

```powershell
.\release.ps1 -Version "1.2.0" -Notes "Kratak opis sta je novo."
```

Za **obaveznu** nadogradnju (korisnik MORA da ažurira, nema dugme „Kasnije"):

```powershell
.\release.ps1 -Version "1.2.0" -Notes "Vazna ispravka." -Mandatory
```

Skripta sama uradi sve: podigne verziju, napravi APK i Windows instaler,
okači ih u repo, napravi `version.json` i pošalje na GitHub.

Kad završi, uradi još samo ovo (da sačuvaš izmjene i u glavnom projektu):

```bash
git add -A && git commit -m "Verzija 1.2.0"
```

**To je sve.** Ostalo (ispod) je ručna varijanta / objašnjenje šta skripta radi.

---

## 🔧 Ručni način — korak po korak (ako skripta zakaže)

Neka je nova verzija npr. **1.2.0**.

1. **Podigni verziju** u `pubspec.yaml` — i naziv i build broj:
   ```yaml
   version: 1.2.0+3      # broj poslije + uvijek mora da raste
   ```

2. **Podigni verziju** u `installer\salon.iss`:
   ```
   #define MyAppVersion "1.2.0"
   ```

3. **Napravi Android APK:**
   ```bash
   flutter build apk --release
   ```
   Izlaz: `build\app\outputs\flutter-apk\app-release.apk`

4. **Napravi Windows aplikaciju pa instaler:**
   ```bash
   flutter build windows --release
   ```
   Zatim otvori `installer\salon.iss` u Inno Setup-u i klikni **Compile**.
   Izlaz: `installer\Output\salon-setup-1.2.0.exe`

5. **Kopiraj oba fajla** u releases repo (`C:\Users\djuro\SalonReleases\AppointmentManagementApps`):
   - APK  →  `apk\salon-1.2.0.apk`
   - EXE  →  `windows\salon-setup-1.2.0.exe`

6. **Izmijeni `version.json`** u tom repou — postavi novu verziju i nove linkove:
   ```json
   {
     "android": {
       "latestVersion": "1.2.0",
       "minVersion": "1.0.0",
       "url": ".../apk/salon-1.2.0.apk"
     },
     "windows": {
       "latestVersion": "1.2.0",
       "minVersion": "1.0.0",
       "url": ".../windows/salon-setup-1.2.0.exe"
     },
     "notes": "Sta je novo."
   }
   ```
   > `minVersion` = `latestVersion`  →  **obavezna** nadogradnja.
   > `minVersion` manji (npr. „1.0.0")  →  **opciona** (ima „Kasnije").

7. **Pošalji na GitHub** iz foldera releases repoa:
   ```bash
   git add -A && git commit -m "Verzija 1.2.0" && git push
   ```

---

## ⚠️ Važno — zapamti

- **Android potpis:** APK se MORA praviti na OVOM računaru (isti potpisni ključ).
  Ako ga napraviš na drugom, telefon neće dozvoliti nadogradnju
  (greška „App not installed"). Rješenje bi bilo pravi „release keystore" —
  reci ako to hoćeš da podesimo.
- **Verzija mora da RASTE.** Ako je `version.json` verzija ista ili manja od one
  na uređaju → nema prompta.
- **Windows upozorenje:** instaler nije potpisan, pa Windows prvi put pokaže plavi
  „Windows protected your PC" → *More info → Run anyway*. To je normalno.
- **Android prvi put:** telefon traži dozvolu „instaliranje nepoznatih aplikacija"
  → dozvoli jednom.
- **Preuzimanje ~60 MB** (APK) → najbolje na WiFi.
- Poslije svakog izdanja **commit-uj i glavni projekat** (jer se `pubspec.yaml` i
  `salon.iss` mijenjaju).
