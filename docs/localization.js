(() => {
  "use strict";

  const translations = {
    ja: {
      pageTitle: "Token Meter - Claude CodeとCodexの利用状況をひと目で",
      metaDescription: "Token Meterは、Claude CodeとCodexの利用状況をメニューバーとウィジェットで確認できるmacOSアプリです。",
      ogDescription: "Claude CodeとCodexの残量を、作業を止めずに確認。",
      topAria: "Token Meter トップへ",
      mainNavAria: "メインナビゲーション",
      mobileNavAria: "モバイルナビゲーション",
      menuAria: "メニューを開く",
      menuCloseAria: "メニューを閉じる",
      brandSubtitle: "macOS 使用量モニター",
      navAbout: "概要",
      navPrivacy: "プライバシー",
      navDownload: "ダウンロード",
      heroImageAlt: "ClaudeとCodexの残り利用可能量を表示するToken Meterの画面",
      eyebrow: "macOS メニューバーユーティリティ",
      heroCopy: "Claude CodeとCodexの利用状況を、<br>作業を止めずに確認。",
      downloadVersion: "Token Meter 1.2.2をダウンロード",
      viewScreens: "画面を見る",
      heroReleaseMeta: "macOS 14以降 · Apple Silicon / Intel · 署名・公証済み",
      summaryAria: "Token Meterの概要",
      providersTitle: "2プロバイダー",
      localTitle: "ローカルファースト",
      localBody: "履歴はこのMacに保存",
      nativeTitle: "4言語対応",
      nativeBody: "日本語 / English / 中文 / 한국어",
      introLabel: "ひと目で確認",
      introTitle: "必要な数字だけを、<br>いつでも見える場所に。",
      introBody: "メニューバーでは残量をすばやく確認。詳しく見たいときはダッシュボードとウィジェットから、5時間枠、週次枠、今日のトークン数を追えます。",
      showcaseAria: "アプリ画面と機能",
      featureOneTitle: "2つのAIを、同じ場所で。",
      featureOneBody: "Claude CodeとCodexを並べて表示。使うプロバイダーだけを選べます。",
      providersImageAlt: "ClaudeとCodexを選択するプロバイダー設定画面",
      providersCaption: "Claude / Codex プロバイダー選択",
      featureTwoTitle: "メニューバーは、あなたの見やすさで。",
      featureTwoBody: "Full、Compact、Icon onlyから選択。残量は5時間枠を基本に、週次枠へ切り替えられます。5時間枠が提供されていない場合は週次枠を自動表示します。",
      displayImageAlt: "メニューバーの表示形式を選択する画面",
      displayCaption: "Full / Compact / アイコンのみ",
      widgetLabel: "デスクトップウィジェット",
      widgetTitle: "残量を、<br>デスクトップの<br>定位置に。",
      widgetBody: "Claude CodeとCodexの残量、5時間枠のリセット、今日のトークン数を、アプリを開かずに確認できます。",
      widgetSizesTitle: "3つのサイズ",
      widgetSizesBody: "Small / Medium / Large",
      widgetOpenTitle: "クリックで開く",
      widgetOpenBody: "そのままダッシュボードへ",
      widgetImageAlt: "ClaudeとCodexの利用状況を折れ線グラフで表示するToken Meterウィジェット",
      widgetCaption: "Largeウィジェット · 7日間の利用推移",
      privacyLabel: "初期設定からプライバシー重視",
      privacyTitle: "使用履歴は、<br>このMacから出さない。",
      privacyBodyOne: "ローカルのセッションログから、トークン数・日時・モデル名だけを集計します。プロンプト本文や応答本文、認証情報は保存しません。",
      privacyBodyTwo: "Claude Pro / Maxの残量確認は任意です。有効にした場合のみ、Claude Codeのサインイン情報を使ってAnthropicの使用量エンドポイントへ問い合わせます。",
      privacyLink: "プライバシーポリシーを読む",
      setupLabel: "セットアップ",
      setupTitle: "数分で準備完了。",
      readyImageAlt: "初期設定の完了を示すToken Meterの画面",
      welcomeImageAlt: "ClaudeとCodexの残量を表示する初期画面",
      downloadLabel: "ダウンロード",
      downloadTitle: "一目で<br>残量確認を。",
      downloadBody: "ZIPを展開し、Token Meter.appをアプリケーションフォルダへ移動してください。",
      downloadMeta: "macOS 14以降 · 約5.6 MB · Developer ID署名・Apple公証済み",
      footerReleases: "リリース",
      footerPrivacy: "プライバシー",
      footerSource: "ソースコード",
      footerLicense: "ライセンス",
      languageAria: "言語を選択",
      copyright: "© 2026 Token Meter · macOSのために開発",
      viewReleases: "リリースノートを見る",
      navReleases: "リリースノート",
      releasesTitle: "リリースノート",
      releasesSubtitle: "Token Meter のアップデート履歴",
      backToHome: "ホームへ戻る"
    },
    en: {
      pageTitle: "Token Meter - Claude Code and Codex usage at a glance",
      metaDescription: "Token Meter is a macOS app that shows Claude Code and Codex usage in the menu bar and widgets.",
      ogDescription: "Check your remaining Claude Code and Codex usage without breaking your flow.",
      topAria: "Back to the top of Token Meter",
      mainNavAria: "Main navigation",
      mobileNavAria: "Mobile navigation",
      menuAria: "Open menu",
      menuCloseAria: "Close menu",
      brandSubtitle: "usage monitor for macOS",
      navAbout: "About",
      navPrivacy: "Privacy",
      navDownload: "Download",
      heroImageAlt: "Token Meter showing remaining Claude and Codex usage",
      eyebrow: "Menu bar utility for macOS",
      heroCopy: "See Claude Code and Codex usage<br>without breaking your flow.",
      downloadVersion: "Download Token Meter 1.2.2",
      viewScreens: "View the app",
      heroReleaseMeta: "macOS 14 or later · Apple Silicon / Intel · Signed and notarized",
      summaryAria: "Token Meter overview",
      providersTitle: "2 providers",
      localTitle: "Local first",
      localBody: "History stays on this Mac",
      nativeTitle: "Four languages",
      nativeBody: "English / 日本語 / 中文 / 한국어",
      introLabel: "At a glance",
      introTitle: "Only the numbers you need,<br>always within sight.",
      introBody: "Check remaining usage in the menu bar. Open the dashboard or widget for the 5-hour limit, weekly limit, and today's token count.",
      showcaseAria: "App screens and features",
      featureOneTitle: "Two AIs. One place.",
      featureOneBody: "See Claude Code and Codex side by side, and choose which providers to display.",
      providersImageAlt: "Provider settings for selecting Claude and Codex",
      providersCaption: "Claude / Codex provider selection",
      featureTwoTitle: "A menu bar that works your way.",
      featureTwoBody: "Choose Full, Compact, or Icon only. Remaining usage defaults to the 5-hour limit, can be switched to weekly, and falls back to weekly whenever a 5-hour limit is unavailable.",
      displayImageAlt: "Screen for choosing the menu bar display format",
      displayCaption: "Full / Compact / Icon only",
      widgetLabel: "Desktop widget",
      widgetTitle: "Keep your limits<br>on the desktop.",
      widgetBody: "See Claude Code and Codex remaining usage, 5-hour resets, and today's token counts without opening the app.",
      widgetSizesTitle: "Three sizes",
      widgetSizesBody: "Small / Medium / Large",
      widgetOpenTitle: "Click to open",
      widgetOpenBody: "Go straight to the dashboard",
      widgetImageAlt: "Token Meter widget showing Claude and Codex usage as line charts",
      widgetCaption: "Large widget · Seven-day usage trend",
      privacyLabel: "Privacy by default",
      privacyTitle: "Your usage history<br>never leaves this Mac.",
      privacyBodyOne: "Token Meter reads only token counts, timestamps, and model names from local session logs. It never stores prompt text, responses, or credentials.",
      privacyBodyTwo: "Checking Claude Pro / Max usage is optional. When enabled, Token Meter uses your Claude Code sign-in only to request Anthropic's usage endpoint.",
      privacyLink: "Read the privacy policy",
      setupLabel: "Setup",
      setupTitle: "Ready in minutes.",
      readyImageAlt: "Token Meter showing that setup is complete",
      welcomeImageAlt: "Token Meter welcome screen showing Claude and Codex usage",
      downloadLabel: "Download",
      downloadTitle: "Check your usage<br>at a glance.",
      downloadBody: "Unzip the archive, then move Token Meter.app to your Applications folder.",
      downloadMeta: "macOS 14 or later · About 5.6 MB · Developer ID signed and Apple notarized",
      footerReleases: "Releases",
      footerPrivacy: "Privacy",
      footerSource: "Source",
      footerLicense: "License",
      languageAria: "Choose language",
      copyright: "© 2026 Token Meter · Built for macOS",
      viewReleases: "Release Notes",
      navReleases: "Releases",
      releasesTitle: "Release Notes",
      releasesSubtitle: "Update history of Token Meter",
      backToHome: "Back to Home"
    },
    "zh-CN": {
      pageTitle: "Token Meter - 一目了然地查看 Claude Code 和 Codex 用量",
      metaDescription: "Token Meter 是一款 macOS 应用，可在菜单栏和小组件中查看 Claude Code 与 Codex 的使用情况。",
      ogDescription: "无需打断工作，即可查看 Claude Code 和 Codex 的剩余用量。",
      topAria: "返回 Token Meter 顶部",
      mainNavAria: "主导航",
      mobileNavAria: "移动端导航",
      menuAria: "打开菜单",
      menuCloseAria: "关闭菜单",
      brandSubtitle: "macOS 用量监控工具",
      navAbout: "概览",
      navPrivacy: "隐私",
      navDownload: "下载",
      heroImageAlt: "显示 Claude 和 Codex 剩余用量的 Token Meter 界面",
      eyebrow: "macOS 菜单栏工具",
      heroCopy: "无需打断工作，<br>随时查看 Claude Code 和 Codex 用量。",
      downloadVersion: "下载 Token Meter 1.2.2",
      viewScreens: "查看界面",
      heroReleaseMeta: "macOS 14 或更高版本 · Apple Silicon / Intel · 已签名并通过公证",
      summaryAria: "Token Meter 概览",
      providersTitle: "2 个提供商",
      localTitle: "本地优先",
      localBody: "历史记录保存在本机",
      nativeTitle: "支持四种语言",
      nativeBody: "中文 / English / 日本語 / 한국어",
      introLabel: "一目了然",
      introTitle: "只看需要的数据，<br>随时尽收眼底。",
      introBody: "在菜单栏快速查看剩余用量，需要详情时，可通过仪表盘和小组件查看 5 小时限额、每周限额和今日 Token 数量。",
      showcaseAria: "应用界面与功能",
      featureOneTitle: "两个 AI，一个位置。",
      featureOneBody: "并排显示 Claude Code 和 Codex，并可只选择需要的提供商。",
      providersImageAlt: "选择 Claude 和 Codex 的提供商设置界面",
      providersCaption: "Claude / Codex 提供商选择",
      featureTwoTitle: "按你的方式显示菜单栏。",
      featureTwoBody: "可选择完整、紧凑或仅图标模式。剩余用量默认显示 5 小时限额，也可切换为每周限额；没有 5 小时限额时会自动改用每周限额。",
      displayImageAlt: "选择菜单栏显示格式的界面",
      displayCaption: "完整 / 紧凑 / 仅图标",
      widgetLabel: "桌面小组件",
      widgetTitle: "让剩余用量，<br>固定在桌面上。",
      widgetBody: "无需打开应用，即可查看 Claude Code 和 Codex 的剩余用量、5 小时重置时间和今日 Token 数量。",
      widgetSizesTitle: "三种尺寸",
      widgetSizesBody: "小 / 中 / 大",
      widgetOpenTitle: "点击即可打开",
      widgetOpenBody: "直接进入仪表盘",
      widgetImageAlt: "用折线图显示 Claude 和 Codex 使用情况的 Token Meter 小组件",
      widgetCaption: "大型小组件 · 七天用量趋势",
      privacyLabel: "默认保护隐私",
      privacyTitle: "使用记录，<br>不会离开这台 Mac。",
      privacyBodyOne: "Token Meter 仅从本地会话日志中统计 Token 数量、时间和模型名称，不会保存提示词、回复正文或认证信息。",
      privacyBodyTwo: "查看 Claude Pro / Max 剩余用量是可选功能。仅在启用后，Token Meter 才会使用 Claude Code 登录信息请求 Anthropic 的用量接口。",
      privacyLink: "阅读隐私政策",
      setupLabel: "设置",
      setupTitle: "几分钟即可完成。",
      readyImageAlt: "显示初始设置已完成的 Token Meter 界面",
      welcomeImageAlt: "显示 Claude 和 Codex 用量的 Token Meter 欢迎界面",
      downloadLabel: "下载",
      downloadTitle: "一目了然，<br>查看剩余用量。",
      downloadBody: "解压 ZIP 文件，然后将 Token Meter.app 移到“应用程序”文件夹。",
      downloadMeta: "macOS 14 或更高版本 · 约 5.6 MB · Developer ID 签名并通过 Apple 公证",
      footerReleases: "版本发布",
      footerPrivacy: "隐私",
      footerSource: "源代码",
      footerLicense: "许可证",
      languageAria: "选择语言",
      copyright: "© 2026 Token Meter · 为 macOS 打造",
      viewReleases: "查看更新日志",
      navReleases: "更新日志",
      releasesTitle: "更新日志",
      releasesSubtitle: "Token Meter 更新历史",
      backToHome: "返回首页"
    },
    ko: {
      pageTitle: "Token Meter - Claude Code와 Codex 사용량을 한눈에",
      metaDescription: "Token Meter는 메뉴 막대와 위젯에서 Claude Code와 Codex 사용량을 확인할 수 있는 macOS 앱입니다.",
      ogDescription: "작업 흐름을 멈추지 않고 Claude Code와 Codex 잔여량을 확인하세요.",
      topAria: "Token Meter 맨 위로",
      mainNavAria: "주요 탐색",
      mobileNavAria: "모바일 탐색",
      menuAria: "메뉴 열기",
      menuCloseAria: "메뉴 닫기",
      brandSubtitle: "macOS 사용량 모니터",
      navAbout: "소개",
      navPrivacy: "개인정보",
      navDownload: "다운로드",
      heroImageAlt: "Claude와 Codex의 남은 사용량을 표시하는 Token Meter 화면",
      eyebrow: "macOS 메뉴 막대 유틸리티",
      heroCopy: "작업 흐름을 멈추지 않고<br>Claude Code와 Codex 사용량을 확인하세요.",
      downloadVersion: "Token Meter 1.2.2 다운로드",
      viewScreens: "화면 보기",
      heroReleaseMeta: "macOS 14 이상 · Apple Silicon / Intel · 서명 및 공증 완료",
      summaryAria: "Token Meter 개요",
      providersTitle: "2개 제공자",
      localTitle: "로컬 우선",
      localBody: "기록은 이 Mac에 저장",
      nativeTitle: "4개 언어 지원",
      nativeBody: "한국어 / English / 日本語 / 中文",
      introLabel: "한눈에 확인",
      introTitle: "필요한 수치만,<br>언제나 한눈에.",
      introBody: "메뉴 막대에서 잔여량을 빠르게 확인하세요. 자세한 내용은 대시보드와 위젯에서 5시간 한도, 주간 한도, 오늘의 토큰 수를 확인할 수 있습니다.",
      showcaseAria: "앱 화면 및 기능",
      featureOneTitle: "두 AI를 한곳에서.",
      featureOneBody: "Claude Code와 Codex를 나란히 표시하고, 사용할 제공자만 선택할 수 있습니다.",
      providersImageAlt: "Claude와 Codex를 선택하는 제공자 설정 화면",
      providersCaption: "Claude / Codex 제공자 선택",
      featureTwoTitle: "내게 맞는 메뉴 막대 표시.",
      featureTwoBody: "전체, 컴팩트, 아이콘 전용 중에서 선택하세요. 잔여량은 기본적으로 5시간 한도를 표시하고 주간 한도로 전환할 수 있으며, 5시간 한도가 없으면 주간 한도를 자동으로 표시합니다.",
      displayImageAlt: "메뉴 막대 표시 형식을 선택하는 화면",
      displayCaption: "전체 / 컴팩트 / 아이콘 전용",
      widgetLabel: "데스크톱 위젯",
      widgetTitle: "남은 사용량을<br>데스크톱에 고정.",
      widgetBody: "앱을 열지 않고 Claude Code와 Codex 잔여량, 5시간 초기화 시간, 오늘의 토큰 수를 확인할 수 있습니다.",
      widgetSizesTitle: "세 가지 크기",
      widgetSizesBody: "소형 / 중형 / 대형",
      widgetOpenTitle: "클릭해서 열기",
      widgetOpenBody: "대시보드로 바로 이동",
      widgetImageAlt: "Claude와 Codex 사용량을 꺾은선 그래프로 표시하는 Token Meter 위젯",
      widgetCaption: "대형 위젯 · 7일 사용량 추이",
      privacyLabel: "기본부터 개인정보 보호",
      privacyTitle: "사용 기록은<br>이 Mac을 떠나지 않습니다.",
      privacyBodyOne: "Token Meter는 로컬 세션 로그에서 토큰 수, 시간, 모델 이름만 집계합니다. 프롬프트와 응답 본문 또는 인증 정보는 저장하지 않습니다.",
      privacyBodyTwo: "Claude Pro / Max 잔여량 확인은 선택 사항입니다. 활성화한 경우에만 Claude Code 로그인 정보를 사용해 Anthropic 사용량 엔드포인트를 요청합니다.",
      privacyLink: "개인정보 처리방침 읽기",
      setupLabel: "설정",
      setupTitle: "몇 분이면 준비 완료.",
      readyImageAlt: "초기 설정 완료를 보여 주는 Token Meter 화면",
      welcomeImageAlt: "Claude와 Codex 사용량을 표시하는 Token Meter 시작 화면",
      downloadLabel: "다운로드",
      downloadTitle: "한눈에<br>잔여량을 확인하세요.",
      downloadBody: "ZIP 압축을 푼 다음 Token Meter.app을 응용 프로그램 폴더로 옮기세요.",
      downloadMeta: "macOS 14 이상 · 약 5.6 MB · Developer ID 서명 및 Apple 공증 완료",
      footerReleases: "릴리스",
      footerPrivacy: "개인정보",
      footerSource: "소스 코드",
      footerLicense: "라이선스",
      languageAria: "언어 선택",
      copyright: "© 2026 Token Meter · macOS를 위해 제작",
      viewReleases: "릴리스 노트 보기",
      navReleases: "릴리스 노트",
      releasesTitle: "릴리스 노트",
      releasesSubtitle: "Token Meter 업데이트 내역",
      backToHome: "홈으로 돌아가기"
    }
  };

  const storageKey = "token-meter-language";

  function normalizeLanguage(language) {
    const value = (language || "").toLowerCase();
    if (value.startsWith("ja")) return "ja";
    if (value.startsWith("zh")) return "zh-CN";
    if (value.startsWith("ko")) return "ko";
    if (value.startsWith("en")) return "en";
    return null;
  }

  function savedLanguage() {
    try {
      const value = localStorage.getItem(storageKey);
      return value && Object.prototype.hasOwnProperty.call(translations, value) ? value : null;
    } catch {
      return null;
    }
  }

  function rememberLanguage(language) {
    try {
      localStorage.setItem(storageKey, language);
    } catch {
      // The page still works when storage is unavailable.
    }
  }

  function browserLanguage() {
    const candidates = navigator.languages || [navigator.language];
    for (const candidate of candidates) {
      const normalized = normalizeLanguage(candidate);
      if (normalized) return normalized;
    }
    return "en";
  }

  function applyLanguage(language, persist = true) {
    const selected = Object.prototype.hasOwnProperty.call(translations, language) ? language : "en";
    const dictionary = translations[selected];
    document.documentElement.lang = selected;
    document.title = dictionary.pageTitle;

    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const value = dictionary[element.dataset.i18n];
      if (value !== undefined) element.textContent = value;
    });

    document.querySelectorAll("[data-i18n-html]").forEach((element) => {
      const value = dictionary[element.dataset.i18nHtml];
      if (value !== undefined) element.innerHTML = value;
    });

    document.querySelectorAll("[data-i18n-alt]").forEach((element) => {
      const value = dictionary[element.dataset.i18nAlt];
      if (value !== undefined) element.setAttribute("alt", value);
    });

    document.querySelectorAll("[data-i18n-aria-label]").forEach((element) => {
      const value = dictionary[element.dataset.i18nAriaLabel];
      if (value !== undefined) element.setAttribute("aria-label", value);
    });

    document.querySelectorAll("[data-i18n-content]").forEach((element) => {
      const value = dictionary[element.dataset.i18nContent];
      if (value !== undefined) element.setAttribute("content", value);
    });

    document.querySelectorAll("[data-language]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.language === selected));
    });

    if (persist) rememberLanguage(selected);
    window.dispatchEvent(new CustomEvent('languagechange', { detail: selected }));
  }

  document.querySelectorAll("[data-language]").forEach((button) => {
    button.addEventListener("click", () => applyLanguage(button.dataset.language));
  });

  applyLanguage(savedLanguage() || browserLanguage(), false);
})();
