; 离线语音工作台 Windows x64 安装包脚本（Inno Setup 6，runner 预装）。
;
; 由 .github/workflows/release.yml 调用，版本与源目录经命令行传入：
;   ISCC /DAppVersion=1.0.1 /DAppSource=<build\windows\voxdesk 绝对路径>
; 产物：<仓库>/build/voxdesk-windows-x64-v<版本>-setup.exe
;
; 注意：本文件含中文，保存为「带 BOM 的 UTF-8」（Inno 6.3 之前的版本
; 只认带 BOM 的 UTF-8），勿用无 BOM 编码覆盖保存。

#define AppName "离线语音工作台"
#define AppExe "voxdesk.exe"

[Setup]
; 固定 AppId：升级/卸载靠它识别既有安装，更换会导致装出第二份
AppId={{7A0F2C9E-3B14-4E8D-9C6A-52F1D3B8E7A0}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
DefaultDirName={autopf}\VoxDesk
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=..\build
OutputBaseFilename=voxdesk-windows-x64-v{#AppVersion}-setup
; 无签名证书：SmartScreen 首次运行会提示，放行方式已写进发布说明
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 用户级安装（{autopf} 解析到 %LocalAppData%\Programs）：免 UAC，
; 程序无服务、无全局注册需求；弹窗允许用户改选「为所有用户安装」
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
; 简体中文向导（Inno Setup 6.3+ 官方自带该语言文件）
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#AppSource}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
