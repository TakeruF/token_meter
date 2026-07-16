using System.Globalization;

namespace TokenMeter.Windows.Setup;

internal sealed record SetupStrings(
    string WindowTitle,
    string Heading,
    string Ready,
    string Installing,
    string Installed,
    string AlreadyInstalled,
    string NewerVersionInstalled,
    string Install,
    string Launch,
    string Cancel,
    string Close,
    string PayloadError,
    string InstallError,
    string SignatureHint,
    string SystemChangesAndPrivacy,
    string PrivacyPolicy,
    string UninstallInstructions)
{
    public static SetupStrings Current { get; } = Create(CultureInfo.CurrentUICulture);

    private static SetupStrings Create(CultureInfo culture)
    {
        return culture.TwoLetterISOLanguageName switch
        {
            "ja" => new(
                "Token Meter セットアップ",
                "Token Meter {0}",
                "このユーザーにToken Meterをインストールします。管理者権限は不要です。",
                "インストールしています…",
                "インストールが完了しました。",
                "このバージョンはすでにインストールされています。",
                "このセットアップより新しいバージョンがすでにインストールされています。",
                "インストール",
                "Token Meterを開く",
                "キャンセル",
                "閉じる",
                "インストーラーに有効なMSIXパッケージが含まれていません。",
                "Token Meterをインストールできませんでした。",
                "パッケージとインストーラーが信頼済み証明書で署名されていることを確認してください。",
                "変更内容: 現在のユーザーへMSIXを登録し、初回起動後はWindowsのLocalStateに設定と利用履歴を保存します。サービス、ドライバー、PATH、ファイアウォールは変更しません。Claude Code・Codex・Copilot CLIのローカル利用ログを読みます。Claudeオンライン利用量照会とログイン時起動は既定で無効です。",
                "プライバシーポリシー",
                "アンインストール方法"),
            "zh" => new(
                "Token Meter 安装程序",
                "Token Meter {0}",
                "为当前用户安装 Token Meter。无需管理员权限。",
                "正在安装…",
                "安装完成。",
                "此版本已安装。",
                "已安装比此安装程序更新的版本。",
                "安装",
                "打开 Token Meter",
                "取消",
                "关闭",
                "安装程序未包含有效的 MSIX 包。",
                "无法安装 Token Meter。",
                "请确认软件包和安装程序均由受信任的证书签名。",
                "系统更改：为当前用户注册 MSIX，并在首次启动后将设置和用量历史记录保存到 Windows LocalState。不会安装服务或驱动程序，也不会修改 PATH 或防火墙。应用会读取 Claude Code、Codex 和 Copilot CLI 的本地用量日志。Claude 在线用量查询和登录时启动默认关闭。",
                "隐私政策",
                "卸载说明"),
            "ko" => new(
                "Token Meter 설치",
                "Token Meter {0}",
                "현재 사용자용 Token Meter를 설치합니다. 관리자 권한은 필요하지 않습니다.",
                "설치 중…",
                "설치가 완료되었습니다.",
                "이 버전은 이미 설치되어 있습니다.",
                "이 설치 프로그램보다 최신 버전이 이미 설치되어 있습니다.",
                "설치",
                "Token Meter 열기",
                "취소",
                "닫기",
                "설치 프로그램에 유효한 MSIX 패키지가 없습니다.",
                "Token Meter를 설치할 수 없습니다.",
                "패키지와 설치 프로그램이 신뢰할 수 있는 인증서로 서명되었는지 확인하세요.",
                "시스템 변경: 현재 사용자용 MSIX를 등록하고 첫 실행 후 설정과 사용 기록을 Windows LocalState에 저장합니다. 서비스, 드라이버, PATH 또는 방화벽은 변경하지 않습니다. Claude Code, Codex, Copilot CLI의 로컬 사용 로그를 읽습니다. Claude 온라인 사용량 조회와 로그인 시 시작은 기본적으로 꺼져 있습니다.",
                "개인정보 처리방침",
                "제거 방법"),
            _ => new(
                "Token Meter Setup",
                "Token Meter {0}",
                "Install Token Meter for the current user. Administrator access is not required.",
                "Installing…",
                "Installation completed.",
                "This version is already installed.",
                "A newer version is already installed.",
                "Install",
                "Open Token Meter",
                "Cancel",
                "Close",
                "The installer does not contain a valid MSIX package.",
                "Token Meter could not be installed.",
                "Make sure the package and installer are signed with a trusted certificate.",
                "System changes: registers a per-user MSIX and, after first launch, stores settings and usage history in Windows LocalState. It does not install a service or driver or change PATH or firewall rules. It reads local usage logs from Claude Code, Codex, and Copilot CLI. Claude online usage lookup and start-at-sign-in are off by default.",
                "Privacy policy",
                "Uninstall instructions"),
        };
    }
}
