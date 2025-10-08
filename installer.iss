[Setup]
AppName=Dext
AppVersion=1.0.6
AppPublisher=ChuiShui233
AppPublisherURL=https://wucode.xyz
AppSupportURL=https://wucode.xyz
AppUpdatesURL=https://wucode.xyz
DefaultDirName={userpf}\Dext
DefaultGroupName=Dext
OutputBaseFilename=DextSetup
OutputDir=Output
AppId=8B5F5F3A-8C2D-4E1B-9F7A-3D8E5C7F9A2B

AppMutex=Global\8B5F5F3A-8C2D-4E1B-9F7A-3D8E5C7F9A2B_Setup

; 压缩设置
Compression=lzma2/ultra64
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4
SolidCompression=yes

; 向导样式
WizardStyle=modern
WizardResizable=yes
DisableWelcomePage=no
DisableDirPage=no

; 自动关闭应用程序
CloseApplications=yes
CloseApplicationsFilter=dext.exe
RestartApplications=no

; 权限和图标
PrivilegesRequired=lowest
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dext.exe

; 版权和许可
AppCopyright=© 2025 ChuiShui233. All rights reserved.
LicenseFile=LICENSE.txt

; 向导图片 - 6.5支持PNG格式和透明度
WizardImageFile=installer\installer_bg.bmp
; 如果有PNG格式的小图标，可以取消下面的注释
; WizardSmallImageFile=assets\images\Dext.png

; 卸载信息显示 - 使用6.5新特性：数字分隔符
UninstallDisplaySize=150_000_000

[Languages]
Name: "chinesesimp"; MessagesFile: "installer/ChineseSimplified.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce
Name: "startmenuicon"; Description: "创建开始菜单快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce

[Icons]
; 当前用户桁面快捷方式
Name: "{userdesktop}\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: desktopicon; Check: not IsAllUsersInstall
; 所有用户桁面快捷方式
Name: "{commondesktop}\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: desktopicon; Check: IsAllUsersInstall

; 当前用户开始菜单快捷方式
Name: "{userprograms}\Dext\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: startmenuicon; Check: not IsAllUsersInstall
Name: "{userprograms}\Dext\卸载 Dext"; Filename: "{uninstallexe}"; Tasks: startmenuicon; Check: not IsAllUsersInstall
; 所有用户开始菜单快捷方式
Name: "{commonprograms}\Dext\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: startmenuicon; Check: IsAllUsersInstall
Name: "{commonprograms}\Dext\卸载 Dext"; Filename: "{uninstallexe}"; Tasks: startmenuicon; Check: IsAllUsersInstall

[Run]
Filename: "{app}\dext.exe"; Description: "运行 Dext"; Flags: nowait postinstall skipifsilent

[Registry]
; 注册 dext:// 自定义URI协议
Root: HKCR; Subkey: "dext"; ValueType: string; ValueName: ""; ValueData: "Dext Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "dext"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCR; Subkey: "dext\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\dext.exe,0"; Flags: uninsdeletekey
Root: HKCR; Subkey: "dext\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\dext.exe"" ""%1"""; Flags: uninsdeletekey

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
var
  AllUsersCheckbox: TNewCheckBox;
  IsUpgradeInstall: Boolean;  // 标记是否为更新安装
  SetupMutex: THandle;  // 安装程序互斥体

function CreateMutex(lpMutexAttributes: Integer; bInitialOwner: Boolean; lpName: String): THandle;
  external 'CreateMutexW@kernel32.dll stdcall';

function GetLastError: DWORD;
  external 'GetLastError@kernel32.dll stdcall';

function ReleaseMutex(hMutex: THandle): Boolean;
  external 'ReleaseMutex@kernel32.dll stdcall';

function FindWindowByClassName(lpClassName, lpWindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';
  
function PostMessage(hWnd: HWND; Msg: UINT; wParam, lParam: Integer): BOOL;
  external 'PostMessageW@user32.dll stdcall';

function GetWindowThreadProcessId(hWnd: HWND; var lpdwProcessId: DWORD): DWORD;
  external 'GetWindowThreadProcessId@user32.dll stdcall';

function OpenProcess(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwProcessId: DWORD): THandle;
  external 'OpenProcess@kernel32.dll stdcall';

function TerminateProcess(hProcess: THandle; uExitCode: UINT): BOOL;
  external 'TerminateProcess@kernel32.dll stdcall';

function CloseHandle(hObject: THandle): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';

const
  WM_CLOSE = $0010;
  PROCESS_TERMINATE = $0001;

function IsAdminUser: Boolean;
begin
  Result := IsAdmin;
end;

{ 检查是否为所有用户安装 }
function IsAllUsersInstall: Boolean;
begin
  // 如果是管理员且复选框存在且被勾选，则为所有用户安装
  if IsAdmin and (AllUsersCheckbox <> nil) and AllUsersCheckbox.Checked then
    Result := True
  else
    Result := False;
end;

function IsDextRunning: Boolean;
var
  hWnd: HWND;
begin
  // 尝试查承Flutter窗口
  hWnd := FindWindowByClassName('FLUTTER_RUNNER_WIN32_WINDOW', '');
  if hWnd <> 0 then
  begin
    Result := True;
    Exit;
  end;
  
  // 尝试查找带Dext标题的窗口
  hWnd := FindWindowByClassName('', 'Dext');
  Result := hWnd <> 0;
end;

{ 关闭Dext程序 }
function CloseDextApplication: Boolean;
var
  hWnd: HWND;
  ProcessId: DWORD;
  hProcess: THandle;
  RetryCount: Integer;
  ResultCode: Integer;
begin
  Result := False;
  
  // 第一步：尝试友好关闭（发送WM_CLOSE）
  RetryCount := 0;
  while IsDextRunning and (RetryCount < 3) do
  begin
    hWnd := FindWindowByClassName('FLUTTER_RUNNER_WIN32_WINDOW', '');
    if hWnd = 0 then
      hWnd := FindWindowByClassName('', 'Dext');
    
    if hWnd <> 0 then
    begin
      PostMessage(hWnd, WM_CLOSE, 0, 0);
      Sleep(1000);
    end;
    RetryCount := RetryCount + 1;
  end;
  
  // 如果友好关闭成功
  if not IsDextRunning then
  begin
    Result := True;
    Exit;
  end;
  
  Exec('taskkill.exe', '/F /IM dext.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  
  if not IsDextRunning then
  begin
    Result := True;
    Exit;
  end;
  
  hWnd := FindWindowByClassName('FLUTTER_RUNNER_WIN32_WINDOW', '');
  if hWnd = 0 then
    hWnd := FindWindowByClassName('', 'Dext');
  
  if hWnd <> 0 then
  begin
    ProcessId := 0;
    GetWindowThreadProcessId(hWnd, ProcessId);
    
    if ProcessId <> 0 then
    begin
      hProcess := OpenProcess(PROCESS_TERMINATE, False, ProcessId);
      
      if hProcess <> 0 then
      begin
        if TerminateProcess(hProcess, 0) then
        begin
          CloseHandle(hProcess);
          
          // 等待并验证进程是否真的终止
          RetryCount := 0;
          while (RetryCount < 5) do
          begin
            Sleep(500);
            if not IsDextRunning then
            begin
              Result := True;
              Exit;
            end;
            RetryCount := RetryCount + 1;
          end;
        end
        else
          CloseHandle(hProcess);
      end;
    end;
  end;
end;

function IsHighContrast: Boolean;
begin
  Result := HighContrastActive;
end;

function BoolToStr(Value: Boolean): String;
begin
  if Value then
    Result := 'True'
  else
    Result := 'False';
end;

procedure AllUsersCheckboxClick(Sender: TObject);
var
  NewPath: String;
begin
  if AllUsersCheckbox.Checked then
  begin
    NewPath := ExpandConstant('{commonpf}\Dext');
    WizardForm.DirEdit.Text := NewPath;
    WizardForm.DirEdit.ReadOnly := True;
    WizardForm.DirBrowseButton.Enabled := False;
  end
  else
  begin
    NewPath := ExpandConstant('{userpf}\Dext');
    WizardForm.DirEdit.Text := NewPath;
    WizardForm.DirEdit.ReadOnly := False;
    WizardForm.DirBrowseButton.Enabled := True;
  end;
end;

procedure InitializeWizard;
var
  DefaultPath: String;
begin
  // 如果是更新安装，修改窗口标题和各页面文本
  if IsUpgradeInstall then
  begin
    WizardForm.Caption := 'Dext 更新向导';
    WizardForm.WelcomeLabel1.Caption := '欢迎使用 Dext 更新向导';
    WizardForm.WelcomeLabel2.Caption := '这将更新您计算机上安装的 Dext 到新版本。' + #13#10#13#10 +
                                        '建议您在继续之前关闭所有其他应用程序。' + #13#10#13#10 +
                                        '点击「下一步」继续，或点击「取消」退出更新向导。';
    WizardForm.FinishedLabel.Caption := 'Dext 已成功更新到您的计算机。';
    WizardForm.ReadyLabel.Caption := '现在已经准备好开始更新。' + #13#10#13#10 +
                                     '点击「更新」继续，或点击「上一步」修改设置。';
  end;
  
  if IsAdminUser then
  begin
    // 管理员模式：创建"为所有用户安装"复选框
    AllUsersCheckbox := TNewCheckBox.Create(WizardForm);
    AllUsersCheckbox.Parent := WizardForm.SelectDirPage;
    AllUsersCheckbox.Left := ScaleX(0);
    AllUsersCheckbox.Top := WizardForm.DirEdit.Top + WizardForm.DirEdit.Height + ScaleY(12);
    AllUsersCheckbox.Caption := '为所有用户安装';
    AllUsersCheckbox.Checked := False;
    AllUsersCheckbox.OnClick := @AllUsersCheckboxClick;

    // 设置默认路径和状态（可编辑）
    DefaultPath := ExpandConstant('{userpf}\Dext');
    WizardForm.DirEdit.Text := DefaultPath;
    WizardForm.DirEdit.ReadOnly := False;
    WizardForm.DirBrowseButton.Enabled := True;
  end
  else
  begin
    // 非管理员模式：只能当前用户安装
    DefaultPath := ExpandConstant('{userpf}\Dext');
    WizardForm.DirEdit.Text := DefaultPath;
    WizardForm.DirEdit.ReadOnly := False;
    WizardForm.DirBrowseButton.Enabled := True;
  end;
end;

{ 控制是否跳过选择目录页面 }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  
  // 如果是更新安装，跳过选择目录、选择任务和选择开始菜单文件夹页面
  if IsUpgradeInstall then
  begin
    if (PageID = wpSelectDir) or (PageID = wpSelectTasks) or (PageID = wpSelectProgramGroup) then
      Result := True;
  end;
end;

{ 页面切换时的处理 }
procedure CurPageChanged(CurPageID: Integer);
var
  I: Integer;
begin
  // 如果是更新安装，修改按钮文本
  if IsUpgradeInstall then
  begin
    if CurPageID = wpReady then
    begin
      // 将"安装"按钮改为"更新"
      WizardForm.NextButton.Caption := '更新(&I)';
    end;
  end;
  
  // 如果选择了为所有用户安装，自动勾选并锁死任务选项
  if CurPageID = wpSelectTasks then
  begin
    if IsAdmin and (AllUsersCheckbox <> nil) and AllUsersCheckbox.Checked then
    begin
      // 自动勾选所有任务
      for I := 0 to WizardForm.TasksList.Items.Count - 1 do
      begin
        WizardForm.TasksList.Checked[I] := True;
      end;
      
      // 禁用任务列表和按钮
      WizardForm.TasksList.Enabled := False;
    end
    else
    begin
      // 如果不是为所有用户安装，确保启用
      WizardForm.TasksList.Enabled := True;
    end;
  end;
end;

{ 检测是否为更新安装 }
function IsExistingInstallation: Boolean;
var
  AppPath: String;
  UninstallKey: String;
  InstallLocation: String;
begin
  Result := False;
  
  // 优先从注册表读取实际安装路径
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\8B5F5F3A-8C2D-4E1B-9F7A-3D8E5C7F9A2B_is1';
  
  // 检查当前用户注册表
  if RegQueryStringValue(HKEY_CURRENT_USER, UninstallKey, 'InstallLocation', InstallLocation) then
  begin
    AppPath := AddBackslash(InstallLocation) + 'dext.exe';
    if FileExists(AppPath) then
    begin
      Result := True;
      Exit;
    end;
  end;
  
  // 检查本地机器注册表
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, UninstallKey, 'InstallLocation', InstallLocation) then
  begin
    AppPath := AddBackslash(InstallLocation) + 'dext.exe';
    if FileExists(AppPath) then
    begin
      Result := True;
      Exit;
    end;
  end;
  
  // 如果注册表中没有找到，检查默认路径
  // 检查当前用户程序目录
  AppPath := ExpandConstant('{userpf}\Dext\dext.exe');
  if FileExists(AppPath) then
  begin
    Result := True;
    Exit;
  end;
  
  // 检查公共程序目录
  AppPath := ExpandConstant('{commonpf}\Dext\dext.exe');
  if FileExists(AppPath) then
  begin
    Result := True;
    Exit;
  end;
  
  // 检查Program Files (x86)
  AppPath := ExpandConstant('{commonpf32}\Dext\dext.exe');
  if FileExists(AppPath) then
  begin
    Result := True;
    Exit;
  end;
  
  // 最后检查注册表项是否存在（但文件可能已被删除）
  if RegKeyExists(HKEY_CURRENT_USER, UninstallKey) or 
     RegKeyExists(HKEY_LOCAL_MACHINE, UninstallKey) then
  begin
    Result := True;
    Exit;
  end;
end;

{ 安装程序启动时的初始化 }
function InitializeSetup(): Boolean;
var
  Response: Integer;
  InstallationType: String;
  ErrorCode: DWORD;
begin
  Result := False;
  
  // 创建全局互斥体防止多个安装程序实例
  SetupMutex := CreateMutex(0, True, 'Global\DextSetup_8B5F5F3A-8C2D-4E1B-9F7A-3D8E5C7F9A2B');
  ErrorCode := GetLastError;
  
  // ERROR_ALREADY_EXISTS = 183
  if ErrorCode = 183 then
  begin
    MsgBox('另一个 Dext 安装程序已在运行，请关闭其他安装程序后再试。', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  
  Result := True;
  
  // 检测是安装还是更新
  IsUpgradeInstall := IsExistingInstallation;
  
  if IsUpgradeInstall then
    InstallationType := '更新'
  else
    InstallationType := '安装';
  
  // 检测Dext是否正在运行
  if IsDextRunning then
  begin
    Response := MsgBox('检测到Dext正在运行，需要关闭后才能继续' + InstallationType + '。' + #13#10#13#10 +
                       '点击"是"自动关闭程序，点击"否"取消' + InstallationType + '。',
                       mbConfirmation, MB_YESNO);
    
    if Response = IDYES then
    begin
      if not CloseDextApplication then
      begin
        MsgBox('无法自动关闭Dext，请手动关闭后重试。', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
  
  // 显示安装类型提示
  if IsUpgradeInstall then
  begin
    MsgBox('检测到已安装的Dext，将执行更新操作。' + #13#10 + 
           '您的数据和设置将被保留。', mbInformation, MB_OK);
  end
  else
  begin
    // 如果不是管理员，提示用户
    if not IsAdmin then
    begin
      MsgBox('提示：当前没有管理员权限，安装将仅限当前用户。' + #13#10 + 
             '若需为所有用户安装，请右键安装程序选择"以管理员身份运行"。', 
             mbInformation, MB_OK);
    end;
  end;
end;

{ 卸载程序启动时的初始化 }
function InitializeUninstall(): Boolean;
var
  Response: Integer;
begin
  Result := True;
  
  // 检测Dext是否正在运行
  if IsDextRunning then
  begin
    Response := MsgBox('检测到Dext正在运行，需要关闭后才能继续卸载。' + #13#10#13#10 +
                       '点击“是”自动关闭程序，点击“否”取消卸载。',
                       mbConfirmation, MB_YESNO);
    
    if Response = IDYES then
    begin
      if not CloseDextApplication then
      begin
        MsgBox('无法自动关闭Dext，请手动关闭后重试。', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ 安装程序退出时的清理 }
procedure DeinitializeSetup();
begin
  // 释放互斥体
  if SetupMutex <> 0 then
  begin
    ReleaseMutex(SetupMutex);
    CloseHandle(SetupMutex);
  end;
end;
