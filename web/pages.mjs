// The site's one source of truth: every page's URL, metadata and FAQ.
// Titles stay under 60 characters and descriptions under 160, so search
// results show them whole; web/tests/site.test.mjs enforces both.

// ponytail: a project-page URL. A custom domain means changing these two
// lines and adding a CNAME file; every canonical, sitemap and link follows.
export const SITE_URL = "https://vette1123.github.io/najm";
export const BASE_PATH = "/najm";

export const REPO_URL = "https://github.com/Vette1123/najm";
export const INDEXNOW_KEY = "6f1d2c7ab3e94d0c8e57a1b46d90c3f2";

const faqEn = [
  [
    "What is Najm?",
    "Najm is a free, open-source terminal emulator for Windows 10 and 11. It is a native Win32 app built on Ghostty's terminal core, with tabs, splits and session restore.",
  ],
  [
    "Is Najm the official Ghostty for Windows?",
    "No. Najm is an independent project built on Ghostty's open-source core through Noctty. It is not affiliated with the Ghostty or Noctty projects. It reads Ghostty's config syntax, so most options and themes work as they are.",
  ],
  [
    "Is Najm free?",
    "Yes. Najm is free and open source under the MIT license, with no account and no paid tier.",
  ],
  [
    "Why does Windows show a SmartScreen warning?",
    "Najm signs its builds with its own certificate, which Windows does not know yet. Click More info, then Run anyway. You can check the download against the published SHA-256 sum first.",
  ],
  [
    "Does Najm collect telemetry?",
    "No. Najm sends no telemetry. Its only network call is the update check against the project's GitHub releases, and you can turn that off.",
  ],
  [
    "Will Najm replace Windows Terminal?",
    "Only if you want it to. Najm installs side by side with Windows Terminal and never touches its settings, so you can try both.",
  ],
];

const faqAr = [
  [
    "ما هو نجم؟",
    "نجم طرفية مجانية مفتوحة المصدر لنظامي ويندوز 10 و11. تطبيق Win32 أصلي مبني على نواة Ghostty، يدعم التبويبات وتقسيم النوافذ واستعادة الجلسة.",
  ],
  [
    "هل يعرض نجم العربية من اليمين إلى اليسار؟",
    "نعم. يعرض نجم العربية من اليمين إلى اليسار في مخرجات الأوامر وعند سطر الأوامر، بحروف موصولة. البرامج التي تملأ الشاشة، مثل vim، تبقى من اليسار إلى اليمين. أضف سطرا واحدا إلى الإعدادات ليستخدم خطا أحادي المسافة يحتوي على العربية.",
  ],
  [
    "هل نجم مجاني؟",
    "نعم. نجم مجاني ومفتوح المصدر برخصة MIT، بلا حساب وبلا اشتراك.",
  ],
  [
    "لماذا يظهر تحذير SmartScreen عند التثبيت؟",
    "يوقّع نجم إصداراته بشهادته الخاصة، ولا يعرفها ويندوز بعد. اضغط More info ثم Run anyway. ويمكنك مطابقة الملف مع بصمة SHA-256 المنشورة قبل التشغيل.",
  ],
  [
    "هل يجمع نجم بيانات عن استخدامي؟",
    "لا. لا يرسل نجم أي بيانات استخدام. اتصاله الوحيد بالشبكة هو فحص التحديثات من إصدارات المشروع على GitHub، ويمكنك إيقافه.",
  ],
];

export const pages = [
  {
    slug: "",
    source: "home",
    lang: "en",
    alternate: "ar/",
    nav: "Home",
    title: "Najm: a fast GPU terminal for Windows, built on Ghostty",
    description:
      "Free native terminal for Windows 10 and 11, built on Ghostty's core. Tabs, splits, session restore and image paste, with PowerShell, WSL and Git Bash.",
    updated: "2026-10-31",
    image: "assets/shot-splits-dark.png",
    software: true,
    faq: faqEn,
  },
  {
    slug: "ghostty-for-windows/",
    source: "ghostty-for-windows",
    lang: "en",
    nav: "Ghostty for Windows",
    title: "Ghostty for Windows: native builds you can install today",
    description:
      "Ghostty has no official Windows release yet. Najm is a signed native Win32 terminal built on Ghostty's core, using the same config syntax and themes.",
    updated: "2026-10-31",
    faq: [
      [
        "Does Ghostty run on Windows?",
        "The Ghostty project does not ship an official Windows app at the time of writing. Community projects build its core for Windows; Najm is one of them, packaged as an installer with built-in updates.",
      ],
      [
        "Can I use my Ghostty config in Najm?",
        "Yes, for most of it. Najm reads the same syntax from %LOCALAPPDATA%\\najm\\config.ghostty, so most options and themes work as they are. Options tied to macOS or Linux do not apply.",
      ],
    ],
  },
  {
    slug: "windows-terminal-alternative/",
    source: "windows-terminal-alternative",
    lang: "en",
    nav: "Windows Terminal alternative",
    title: "A Windows Terminal alternative built on Ghostty | Najm",
    description:
      "Thinking of leaving Windows Terminal? Najm installs beside it and adds Ghostty's core and config. See what differs and how each setting translates.",
    updated: "2026-10-31",
    faq: [
      [
        "Can I run Najm and Windows Terminal together?",
        "Yes. They install side by side. Najm does not read or change Windows Terminal's settings.json, and does not change your default terminal.",
      ],
      [
        "Can Najm import my Windows Terminal settings?",
        "No, there is no importer. The two use different config models, so copy the lines you need using the table on this page.",
      ],
    ],
  },
  {
    slug: "arabic-terminal-windows/",
    source: "arabic-terminal-windows",
    lang: "en",
    nav: "Arabic text",
    title: "Arabic in a Windows terminal: right to left, fonts | Najm",
    description:
      "Najm shows Arabic and Hebrew right to left on Windows, letters joined. Set a monospace font with one config line, and see where the limits are.",
    updated: "2026-11-01",
    faq: [
      [
        "Does Najm display Arabic right to left?",
        "Yes, in command output and at the prompt, with joined letters. Full-screen apps such as vim stay left to right, because they place every cell themselves.",
      ],
      [
        "Why does Arabic look uneven in my terminal?",
        "Most terminal fonts have no Arabic, so Windows draws it in a proportional font that sits unevenly in the cell grid. Map the Arabic blocks to a monospace font that has them.",
      ],
      [
        "Which font should I use for Arabic?",
        "The current release of Cascadia Code from Microsoft's GitHub has Arabic. The copy that ships with Windows does not, so install the release.",
      ],
    ],
  },
  {
    slug: "paste-images-claude-code-windows/",
    source: "paste-images",
    lang: "en",
    nav: "Paste images in Claude Code",
    title: "Paste screenshots into Claude Code on Windows | Najm",
    description:
      "One config line makes Ctrl+V in Najm paste text, copied files and images, so Claude Code and opencode can attach screenshots on Windows.",
    updated: "2026-10-31",
    faq: [
      [
        "Why can't I paste an image into a terminal app on Windows?",
        "A terminal only sends text. An image-aware app has to be told a paste happened so it can read the clipboard itself. Najm sends an empty bracketed paste for that, the way Windows Terminal does.",
      ],
    ],
  },
  {
    slug: "download/",
    source: "download",
    lang: "en",
    nav: "Download",
    title: "Download Najm for Windows: installer and portable ZIP",
    description:
      "Download Najm for Windows 10 and 11 on x64 as an installer or portable ZIP. How to get past SmartScreen and check the file's SHA-256 before you run it.",
    updated: "2026-10-31",
    software: true,
  },
  {
    slug: "ar/",
    source: "ar",
    lang: "ar",
    alternate: "",
    nav: "الرئيسية",
    title: "نجم: طرفية سريعة لويندوز مبنية على Ghostty",
    description:
      "نجم طرفية مجانية لويندوز 10 و11 مبنية على نواة Ghostty، مع التبويبات وتقسيم النوافذ واستعادة الجلسة ولصق الصور في أدوات الذكاء الاصطناعي.",
    updated: "2026-10-31",
    image: "assets/shot-splits-dark.png",
    software: true,
    faq: faqAr,
  },
];

export const ui = {
  en: {
    dir: "ltr",
    locale: "en_US",
    skip: "Skip to content",
    download: "Download",
    github: "GitHub",
    menu: [
      ["ghostty-for-windows/", "Ghostty for Windows"],
      ["windows-terminal-alternative/", "Compare"],
      ["arabic-terminal-windows/", "Arabic"],
      ["ar/", "العربية"],
    ],
    faqTitle: "Questions",
    closeTitle: "Try Najm on your machine",
    closeText: "Free and open source. It installs beside your current terminal.",
    relatedTitle: "More about Najm",
    home: "Home",
    footer:
      "Najm is an independent project, not affiliated with the Ghostty or Noctty projects. MIT license.",
    copy: "Copy",
    copied: "Copied",
    logoAlt: "Najm home",
    socialAlt: "The Najm star mark and the line: a fast GPU terminal for Windows.",
  },
  ar: {
    dir: "rtl",
    locale: "ar_AR",
    skip: "انتقل إلى المحتوى",
    download: "تنزيل",
    github: "GitHub",
    menu: [
      ["arabic-terminal-windows/", "دليل العربية"],
      ["download/", "التثبيت"],
      ["", "English"],
    ],
    faqTitle: "أسئلة شائعة",
    closeTitle: "جرّب نجم على جهازك",
    closeText: "مجاني ومفتوح المصدر، ويعمل إلى جانب طرفيتك الحالية.",
    relatedTitle: "المزيد عن نجم",
    home: "الرئيسية",
    footer: "نجم مشروع مستقل، ولا يتبع مشروعي Ghostty أو Noctty. رخصة MIT.",
    copy: "نسخ",
    copied: "تم النسخ",
    logoAlt: "الصفحة الرئيسية لنجم",
    socialAlt: "شعار نجم على شكل نجمة، مع العبارة: طرفية سريعة لويندوز.",
  },
};
