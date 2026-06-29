# 📘 Komande i kratki tutorijal za Flutter

Ovaj fajl ti pomaže da **pokreneš, izgradiš i razumiješ** ovu aplikaciju, čak i ako
nikada prije nisi koristio Flutter ili Dart.

---

## 1) Šta su Flutter i Dart? (ukratko)

- **Dart** je programski jezik (sličan Javi i JavaScript-u).
- **Flutter** je alat koji od Dart koda pravi aplikacije za Android, iOS, Web i desktop
  iz **jednog koda**.
- U Flutteru je **sve „Widget“** — dugme, tekst, ekran, lista... sve je widget.
  Widgete slažeš jedan u drugi (kao Lego kocke) i tako gradiš ekran.

---

## 2) Prvi put — instalacija alata

1. Instaliraj Flutter SDK: https://docs.flutter.dev/get-started/install
2. Provjeri da je sve spremno:

```bash
flutter doctor
```

> `flutter doctor` ti kaže šta fali (npr. Android Studio, emulator...). Riješi sve
> crvene `[✗]` stavke prije nastavka.

---

## 3) Najvažnije komande (redom kako se koriste)

### a0) PRVI PUT: generiši platformske foldere (android/ios/web)

Ovaj projekat sadrži `lib/` kod, `pubspec.yaml` i dokumentaciju, ali NE sadrži
foldere za Android/iOS/Web (oni su veliki i prave se automatski). Pokreni jednom:

```bash
flutter create --project-name salon_management --platforms=android,ios,web .
```

> Ova komanda NEĆE obrisati postojeći `lib/` kod ni `pubspec.yaml` — samo dodaje
> ono što fali (native foldere). Tačka `.` na kraju znači „u ovom folderu“.

**Android + localhost:** ako serveru pristupaš preko `http://` (ne `https`), Android
u release modu blokira „nešifrovani“ saobraćaj. Za razvoj, u
`android/app/src/main/AndroidManifest.xml` na `<application>` tag dodaj:
`android:usesCleartextTraffic="true"`. U istom fajlu, iznad `<application>`,
dodaj i dozvolu za internet (za release verziju):
`<uses-permission android:name="android.permission.INTERNET"/>`.

### a) Preuzmi sve biblioteke (dependencije) iz `pubspec.yaml`

```bash
flutter pub get
```

### b) Generiši kod (OBAVEZNO prije prvog pokretanja!)

Ova aplikacija koristi **Freezed**, **Retrofit** i **json_serializable**. Oni
„dopisuju“ dio koda umjesto tebe u fajlove `*.g.dart` i `*.freezed.dart`.
Bez ovog koraka aplikacija se NEĆE pokrenuti.

```bash
# Jednokratno generisanje:
dart run build_runner build --delete-conflicting-outputs
```

```bash
# ILI: automatski regeneriši svaki put kad nešto promijeniš (ostavi da radi u pozadini):
dart run build_runner watch --delete-conflicting-outputs
```

> Kad vidiš grešku tipa „part 'nesto.g.dart' not found“ — to znači da samo treba
> pokrenuti komandu iznad.

### c) Pokreni aplikaciju

```bash
# Prikaži dostupne uređaje/emulatore:
flutter devices

# Pokreni na trenutno povezanom uređaju/emulatoru:
flutter run

# Pokreni baš u Chrome pregledaču (najlakše za probu):
flutter run -d chrome
```

> Dok aplikacija radi, pritisni **`r`** u terminalu za „hot reload“ (trenutna
> izmjena bez gubitka stanja), ili **`R`** za „hot restart“.

### d) Izgradi finalnu (release) verziju

```bash
# Android APK (instalacioni fajl):
flutter build apk --release

# Android App Bundle (za Google Play):
flutter build appbundle --release

# Web verzija (folder build/web):
flutter build web --release

# iOS (samo na Mac-u):
flutter build ios --release
```

### e) Korisne pomoćne komande

```bash
flutter analyze        # Provjeri kod (linter) — traži greške i loše prakse
flutter test           # Pokreni testove
flutter clean          # Obriši build keš (kad nešto „čudno“ ne radi)
flutter pub upgrade    # Ažuriraj biblioteke na novije verzije
```

> Tipičan „reset“ kad ništa ne radi:
> ```bash
> flutter clean
> flutter pub get
> dart run build_runner build --delete-conflicting-outputs
> flutter run
> ```

---

## 4) Gdje je šta u projektu (struktura)

```
lib/
├── main.dart                 # Ulazna tačka aplikacije (start)
├── core/                     # Osnovne stvari: tema, konstante, greške
│   ├── config.dart           # Adresa servera (baseUrl) i ostala podešavanja
│   ├── theme.dart            # Boje i izgled (Material 3)
│   └── exceptions.dart       # Klase za greške
├── services/                 # „Servisi“ — komunikacija sa serverom i čuvanje tokena
│   ├── token_storage.dart    # Sigurno čuvanje JWT tokena
│   ├── dio_client.dart       # Podešen Dio HTTP klijent
│   ├── auth_interceptor.dart # Automatski dodaje token i osvježava ga
│   └── api_service.dart      # Retrofit API (svi pozivi ka serveru)
├── models/                   # Modeli podataka (Freezed klase iz OpenAPI spec.)
├── shared/                   # Dijeljeni widgeti (dugmad, polja, prazna stanja...)
├── router/                   # Definicija ruta (GoRouter) + zaštita po ulozi
└── features/                 # Ekrani po funkcionalnostima
    ├── auth/                 # Prijava (login)
    ├── dashboard/            # Početni ekran
    ├── customers/            # Klijenti (CRUD + paginacija)
    ├── employees/            # Zaposleni (CRUD)
    ├── services/             # Usluge (CRUD)
    ├── products/             # Proizvodi (CRUD)
    ├── appointments/         # Termini (lista/kalendar + paginacija)
    └── reports/              # Izvještaji (prihodi)
```

---

## 5) Kako aplikacija „razmišlja“ (arhitektura u 4 koraka)

1. **Model** (`models/`) = oblik podatka (npr. `CustomerResponse` ima `id`, `name`...).
2. **API servis** (`services/api_service.dart`) = poziva server i vraća modele.
3. **Provider** (Riverpod, u svakom feature-u) = drži podatke i logiku za ekran.
4. **Ekran/Widget** (`features/`) = crta podatke i reaguje na klikove.

Riverpod ukratko:
- `Provider` — drži nešto što se ne mijenja (npr. instancu servisa).
- `FutureProvider` — drži podatke koji se učitavaju sa servera (ima loading/error/data).
- `StateNotifierProvider` — drži stanje koje se mijenja (npr. lista sa paginacijom).
- U widgetu koristiš `ref.watch(...)` da „slušaš“ podatke i `ref.read(...)` za akcije.

---

## 6) Podešavanje adrese servera

Server adresa se nalazi u `lib/core/config.dart`:

```dart
static const String baseUrl = 'http://localhost:8080';
```

- **Web / iOS simulator:** `http://localhost:8080`
- **Android emulator:** koristi `http://10.0.2.2:8080` (emulator ne vidi „localhost“
  računara direktno).
- **Pravi telefon:** koristi IP adresu računara, npr. `http://192.168.1.10:8080`.

---

## 7) Česti problemi i rješenja

| Problem | Rješenje |
|--------|----------|
| `Target of URI hasn't been generated` | Pokreni `dart run build_runner build --delete-conflicting-outputs` |
| Aplikacija ne može da se poveže sa serverom (Android) | Promijeni `baseUrl` na `http://10.0.2.2:8080` |
| Bijeli ekran / čudne greške | `flutter clean` pa ponovo `pub get` i `run` |
| Token istekao, izbacuje me | To je normalno — interceptor pokušava `refresh`, ako ne uspije vraća na login |

Srećno! 🎉
