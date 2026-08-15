; ============================================================================
;  Inno Setup skripta za "Salon Menadžment" (Windows instaler + auto-update)
; ============================================================================
;
;  ZAŠTO: Windows nema prodavnicu aplikacija, pa nadogradnja ide preko malog
;  instalera. Aplikacija ga preuzme i pokrene; instaler zatvori staru verziju,
;  zamijeni fajlove i pokrene novu.
;
;  KAKO SE KORISTI (jednom podesiš, pa ponavljaš pri svakom izdanju):
;    1. Instaliraj Inno Setup (besplatno): https://jrsoftware.org/isdl.php
;    2. Napravi Windows build:   flutter build windows --release
;       (izlaz je u:  build\windows\x64\runner\Release\ )
;    3. Otvori ovaj fajl u Inno Setup-u i klikni "Compile".
;       Dobiješ:  installer\Output\salon-setup-<verzija>.exe
;    4. Taj .exe postavi kao "Release" prilog na GitHub i upiši njegov link
;       u "windows" -> "url" u fajlu version.json.
;
;  PRI SVAKOM NOVOM IZDANJU: promijeni samo MyAppVersion ispod (i pubspec.yaml).
; ============================================================================

#define MyAppName "Salon Menadžment"
#define MyAppVersion "1.8.5"                    ; <-- promijeni pri svakom izdanju
#define MyAppExeName "salon_management.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId mora ostati ISTI kroz sva izdanja (tako Windows zna da je ista aplikacija).
; Generiši svoj GUID u Inno Setup-u: Tools -> Generate GUID, pa ga zalijepi ovdje.
AppId={{5F1B9E42-3C7A-4D1E-9B2F-8A6C0D4E7F11}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\SalonManagement
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=salon-setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Instalacija u korisnički folder → NE traži administratorska prava (bez UAC prozora).
PrivilegesRequired=lowest
; Ako je aplikacija pokrenuta, zatvori je (da se fajlovi mogu zamijeniti) pa je opet pokreni.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
; Na kraju instalacije automatski pokreni aplikaciju (bešavan „update" doživljaj).
Filename: "{app}\{#MyAppExeName}"; Description: "Pokreni {#MyAppName}"; Flags: nowait postinstall skipifsilent
