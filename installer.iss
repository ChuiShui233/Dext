[Setup]
AppName=Dext
AppVersion=1.0.2
AppPublisher=ChuiShui233
AppPublisherURL=https://wucode.xyz
AppSupportURL=https://wucode.xyz
AppUpdatesURL=https://wucode.xyz
DefaultDirName={userpf}\Dext
DefaultGroupName=Dext
OutputBaseFilename=DextSetup
OutputDir=Output

; 压缩设置 - 使用6.5新特性：增强的LZMA多线程压缩
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

;----------------------------------------
; 语言设置
;----------------------------------------
[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

;----------------------------------------
; 文件复制
;----------------------------------------
[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

;----------------------------------------
; 安装任务
;----------------------------------------
[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce
Name: "startmenuicon"; Description: "创建开始菜单快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce

;----------------------------------------
; 快捷方式
;----------------------------------------
[Icons]
; 桌面快捷方式（仅在用户勾选时创建）
Name: "{autodesktop}\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: desktopicon

; 开始菜单文件夹快捷方式（仅在用户勾选时创建）
Name: "{group}\Dext"; Filename: "{app}\dext.exe"; WorkingDir: "{app}"; Tasks: startmenuicon
Name: "{group}\卸载 Dext"; Filename: "{uninstallexe}"; Tasks: startmenuicon

;----------------------------------------
; 安装完成后运行
;----------------------------------------
[Run]
Filename: "{app}\dext.exe"; Description: "运行 Dext"; Flags: nowait postinstall skipifsilent

;----------------------------------------
; 卸载部分
;----------------------------------------
[UninstallDelete]
Type: filesandordirs; Name: "{app}"

;----------------------------------------
; 自定义安装页面（是否为所有用户安装）
;----------------------------------------
[Code]
var
  AllUsersCheckbox: TNewCheckBox;

{ 外部函数声明 }
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

{ 检测是否为管理员用户 }
function IsAdminUser: Boolean;
begin
  Result := IsAdmin;
end;

{ 检测Dext是否正在运行 }
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
  
  // 第二步：尝试taskkill命令
  Exec('taskkill.exe', '/F /IM dext.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  
  if not IsDextRunning then
  begin
    Result := True;
    Exit;
  end;
  
  // 第三步：强制终止进程
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

{ 检测高对比度模式 - Inno Setup 6.5.0 新增 }
function IsHighContrast: Boolean;
begin
  Result := HighContrastActive;
end;

{ 布尔值转字符串辅助函数 }
function BoolToStr(Value: Boolean): String;
begin
  if Value then
    Result := 'True'
  else
    Result := 'False';
end;

{ 处理“为所有用户安装”复选框点击事件 }
procedure AllUsersCheckboxClick(Sender: TObject);
var
  NewPath: String;
begin
  if AllUsersCheckbox.Checked then
  begin
    // 为所有用户安装：设置固定路径并锁定
    NewPath := ExpandConstant('{commonpf}\Dext');
    WizardForm.DirEdit.Text := NewPath;
    WizardForm.DirEdit.ReadOnly := True;
    WizardForm.DirBrowseButton.Enabled := False;
  end
  else
  begin
    // 仅为当前用户安装：解锁路径选择
    NewPath := ExpandConstant('{userpf}\Dext');
    WizardForm.DirEdit.Text := NewPath;
    WizardForm.DirEdit.ReadOnly := False;
    WizardForm.DirBrowseButton.Enabled := True;
  end;
end;

{ 初始化向导页面 - 添加自定义UI元素 }
procedure InitializeWizard;
var
  DefaultPath: String;
begin
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

{ 安装程序启动时的初始化 }
function InitializeSetup(): Boolean;
var
  Response: Integer;
begin
  Result := True;
  
  // 检测Dext是否正在运行
  if IsDextRunning then
  begin
    Response := MsgBox('检测到Dext正在运行，需要关闭后才能继续安装。' + #13#10#13#10 +
                       '点击“是”自动关闭程序，点击“否”取消安装。',
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
  
  // 如果不是管理员，提示用户
  if not IsAdmin then
  begin
    MsgBox('提示：当前没有管理员权限，安装将仅限当前用户。' + #13#10 + 
           '若需为所有用户安装，请右键安装程序选择“以管理员身份运行”。', 
           mbInformation, MB_OK);
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
