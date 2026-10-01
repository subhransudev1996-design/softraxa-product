; Inno Setup script for Dukania (Windows desktop build).
; Build the app first, then the installer (from apps\mobile):
;   flutter build windows --release
;   ISCC windows\installer\softraxa_inventory.iss
; The version comes from pubspec.yaml unless passed: ISCC /DMyAppVersion=1.2.0 ...
; Output: build\installer_output\Dukania-Setup-<version>.exe

#define MyAppName "Dukania"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "SOFTRAXA"
#define MyAppURL "https://www.softraxa.in"
#define MyAppExeName "softraxa_inventory.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Never change AppId: it is how Windows recognises an upgrade.
AppId={{6E7C7E7B-9A1E-4B7A-9C7B-1F5B5D8C9A11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=Copyright (C) {#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Shop PCs often run without administrator rights: offer "just for me"
; (no admin needed) as well as "all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
OutputDir=..\..\build\installer_output
OutputBaseFilename=Dukania-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Upgrading closes a running Dukania first and reopens it afterwards.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Build leftovers (.lib/.exp) are not needed to run.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Open {#MyAppName}"; Flags: nowait postinstall skipifsilent
