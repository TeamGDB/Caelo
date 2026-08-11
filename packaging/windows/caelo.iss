; Inno Setup script for the Windows installer.
;
; Built by packaging/windows/package.sh, which passes the version and the
; directory to package. Kept as a file rather than generated so that what the
; installer does is reviewable in one place.

#define AppName "Caelo"
#define AppPublisher "TeamGDB"
#define AppURL "https://github.com/TeamGDB/Caelo"
#define AppExe "caelo.exe"

[Setup]
AppId={{7C1D4A6E-2B3F-4E8A-9C5D-1F0A2B3C4D5E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
#ifdef WithService
; Registering a service needs an administrator, and there is no way to ask for
; one later: the app itself never elevates, which is the whole point of the
; arrangement. Asked once here, never again.
PrivilegesRequired=admin
#else
; Without the service there is nothing to register, so nothing to elevate for.
PrivilegesRequiredOverridesAllowed=dialog
#endif
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
#ifdef WithService
; Registers the tunnel service and asks the Service Control Manager to start it
; when the app opens its pipe. Nothing runs at boot and nothing runs between
; sessions: the service exists only while a tunnel does.
Filename: "{app}\caelo-service.exe"; Parameters: "install"; StatusMsg: "Registering the tunnel service"; Flags: runhidden
#endif
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#ifdef WithService
[UninstallRun]
; Before the files go, not after. Stopping the service is what restores the
; machine's routing, and the binary that knows how to undo it has to still be
; on disk to do so.
Filename: "{app}\caelo-service.exe"; Parameters: "uninstall"; RunOnceId: "RemoveCaeloService"; Flags: runhidden
#endif
