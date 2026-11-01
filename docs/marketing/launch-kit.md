# Najm launch kit

Search only finds Najm once other sites link to it. The website does the
on-page work; these posts earn the links. Everything here is ready to paste.
Post one a day, reply to every comment, and post nothing the app cannot back.

Install counts: `gh api repos/Vette1123/najm/releases --jq '.[].assets[].download_count'`.
Traffic and referrers: `gh api repos/Vette1123/najm/traffic/popular/referrers`.

## Order

| # | Where | Why | Time |
|---|---|---|---|
| 1 | Bing Webmaster Tools | Google Search Console is verified; Bing imports it | 5 min |
| 2 | WinGet | `winget search terminal` is a permanent install channel | 20 min |
| 3 | AlternativeTo | Ranks for "Windows Terminal alternatives" and "Ghostty alternatives" | 10 min |
| 4 | Show HN | The largest single audience for a new terminal | 10 min, then a day of replies |
| 5 | Reddit, one community per day | Each is a separate audience | 10 min each |
| 6 | awesome-terminals | A lasting link from a list people browse | 5 min |

## Search engines

Google Search Console is verified and the sitemap is submitted. Bing Webmaster
Tools can import the property from it, and the site notifies Bing through
IndexNow on every deploy.

## WinGet

Run this once per new package; it reads the installer and opens the pull
request to `microsoft/winget-pkgs` from your account:

```powershell
wingetcreate new https://github.com/Vette1123/najm/releases/download/v1.0.6/najm-1.0.6-windows-x64-setup.exe
```

Use `Vette1123.Najm` as the identifier. The self-signed certificate may slow the
review or trigger a SmartScreen question from the validation bot; answer it
with the verification section of the download page.

## AlternativeTo

Add Najm at <https://alternativeto.net/software/new/> as an alternative to
Windows Terminal, Ghostty, WezTerm and Alacritty.

```text
Najm is a free, open-source terminal emulator for Windows, built on Ghostty's terminal core. It has native tabs and splits, session restore, and a command palette. Ctrl+V can paste screenshots into tools like Claude Code. It runs PowerShell, cmd, Git Bash and WSL with no setup.
```

Tags: `terminal-emulator`, `windows`, `gpu-acceleration`, `open-source`.

## Show HN

Title:

```text
Show HN: Najm, a native Ghostty-based terminal for Windows
```

URL:

```text
https://vette1123.github.io/najm/
```

First comment:

```text
I wanted Ghostty on Windows. Najm is a fork of Noctty, which put Ghostty's core in a native Win32 app, with my own fixes on top.

What it adds for me: Ctrl+V that pastes images into tools like Claude Code, and a session that comes back after a restart.

The rough edge is signing. Builds use my own certificate, so SmartScreen warns on first install. The download page shows how to check the SHA-256 and the signature first.

New in 1.0.9: Arabic and Hebrew read right to left in command output. Full-screen apps such as vim stay left to right.

Tell me what breaks.
```

## Reddit

Read each community's self-promotion rules first. Post where you can answer
questions the same day.

r/commandline and r/PowerShell title:

```text
I built a Ghostty-based terminal for Windows: tabs, splits, session restore, no telemetry
```

r/Windows11 and r/windows title:

```text
Free native terminal for Windows with tabs, splits and session restore (open source)
```

r/ClaudeAI and r/ClaudeCode title:

```text
Paste screenshots into Claude Code on Windows with one config line in Najm
```

Body for all three:

```text
Najm is a free, open-source terminal for Windows built on Ghostty's core. It's a native Win32 app that finds PowerShell, cmd, Git Bash and your WSL distros on its own, and brings back your tabs and splits after a restart.

It installs beside Windows Terminal and doesn't touch its settings, so trying it is safe. SmartScreen will warn you on first install because I sign it with my own certificate; the download page shows how to verify the file first.

Site: https://vette1123.github.io/najm/
Source: https://github.com/Vette1123/najm

Feedback and bug reports are welcome.
```

## Arabic communities

Post this only with the limit stated. Good places: Arabic developer groups on Facebook, LinkedIn, X and Telegram, and
Hsoub I/O (`io.hsoub.com`).

```text
طرفية ويندوز مجانية مبنية على Ghostty

بنيت نجم، طرفية مجانية مفتوحة المصدر لويندوز مبنية على نواة Ghostty. تدعم التبويبات وتقسيم النوافذ وتعيد الجلسة بعد إعادة التشغيل، وتعمل مع PowerShell وGit Bash وWSL دون إعداد. وتعرض العربية من اليمين إلى اليسار في مخرجات الأوامر.

جرّبها وأخبرني بما يحتاج إلى تحسين:
https://vette1123.github.io/najm/ar/
```

## X and LinkedIn

Attach `web/assets/shot-splits-dark.png`, or better, a short recording.

```text
I wanted Ghostty on Windows, so I built Najm.

Native tabs and splits, session restore, a command palette, and Ctrl+V that pastes screenshots into Claude Code.

Free and open source: https://vette1123.github.io/najm/
```

## awesome-terminals

Open a pull request on <https://github.com/cdleon/awesome-terminals> adding this
line to its Windows or cross-platform section, following the list's own format:

```markdown
- [Najm](https://github.com/Vette1123/najm) - Native Windows terminal built on Ghostty's core, with tabs, splits and session restore.
```

## Repository social preview

GitHub has no API for this. Open
<https://github.com/Vette1123/najm/settings>, go to Social preview, and upload
`assets/brand/najm-social.png`. Links shared to the repo then show the Najm card.
