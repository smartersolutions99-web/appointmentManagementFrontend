; ============================================================================
;  Inno Setup skripta za "Salon Menadžment" desktop aplikaciju
;  Pravi jedan setup.exe koji klijent dvaput klikne i instalira aplikaciju.
;  Ne traži developer mode niti sertifikat (radi i bez potpisa).
;
;  Kako koristiti:
;    1. Instaliraj Inno Setup: https://jrsoftware.org/isdl.php
;    2. Prvo napravi release build:  flutter build windows --release
;    3. Otvori ovaj fajl u Inno Setup-u i klikni Build > Compile (ili F9)
;    4. Rezultat je u folderu "installer_output\SalonMenadzment-Setup.exe"
; ============================================================================

#define MyAppName "Salon Menadzment"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Smart Business"
#define MyAppExeName "salon_management.exe"

[Setup]
; AppId jedinstveno identifikuje aplikaciju (za update-ove ostavi isti GUID).
AppId={{8F3C2A91-7B6E-4D52-9A14-2E0F1C5B7D33}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Per-user instalacija u AppData — BEZ admin/UAC prompta.
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=SalonMenadzment-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Aplikacija je 64-bitna.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; "lowest" = instalira se samo za trenutnog korisnika, bez administratorskih
; dozvola (nema UAC prompta). Za instalaciju u Program Files za sve korisnike
; promijeni na "admin" i DefaultDirName na {autopf}\{#MyAppName}.
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Napravi precicu na radnoj povrsini"; GroupDescription: "Dodatne precice:"; Flags: unchecked

[Files]
; Pakujemo CIJELI Release folder (exe + dll-ovi + data folder su obavezni).
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; {autodesktop} = desktop prečica za trenutnog korisnika (radi i bez admina).
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Pokreni aplikaciju"; Flags: nowait postinstall skipifsilent
