# RSS-Feed-Notifications

Windows toast notifications for new items in RSS/Atom feeds, written in PowerShell 7 with the
[BurntToast](https://github.com/Windos/BurntToast) module.

The script runs in a loop, checks your feeds every 5 minutes and shows one notification per new
article, with the feed's favicon, a preview image (if the article has one), a short text and three
buttons: **Read later**, **Archive** and **Dismiss**.

## Requirements

- Windows 10 or 11
- **PowerShell 7 or newer** (`pwsh`). Windows PowerShell 5.1 does not work, the script uses the `??` operator.
- The BurntToast module. The script installs it for the current user on the first start.

## Quick start

1. Download `rss-feed-notifier.ps1`.
2. Open the file and put your feeds into `$RssFeedUrls` (the list contains four example feeds).
3. Start it:

```powershell
pwsh -ExecutionPolicy Bypass -File .\rss-feed-notifier.ps1
```

The first start may ask whether to install the module from the PowerShell Gallery. Answer `Y`.

## Settings

All settings are variables at the top of the script (region `Configuration`):

| Variable | Default | Meaning |
|---|---|---|
| `$RssFeedUrls` | 4 example feeds | The feeds to watch (RSS and Atom) |
| `$CheckIntervalSeconds` | `300` | How often the feeds are checked |
| `$MaxItemsPerFeed` | `5` | How many of the newest items per feed are looked at |
| `$EnableSound` / `$SoundScheme` | `$true` / `"Default"` | Notification sound (`Default`, `SMS`, `Reminder`, `Alarm`, `Mail`) |
| `$EnableImages` | `$true` | Show the article's preview image |
| `$MaxHistoryItems` | `200` | How many already-notified links are remembered per feed |
| `$ImageCacheDays` | `7` | Downloaded images older than this are deleted |

## What it saves, and where

Everything goes to your temp folder (`%TEMP%`):

| File or folder | Content |
|---|---|
| `rss_notifier_history_v5.json` | Links that were already notified, grouped by feed. They are not notified again. |
| `<domain>_favicon.ico` | The favicon of each feed, used as notification icon |
| `RSS_<hash>.jpg` (and similar) | Cached preview images |
| `RSS_ReadLater\` | `.url` shortcuts of the articles for which you clicked **Read later** |
| `RSS_Archive\` | `.url` shortcuts of the articles for which you clicked **Archive** |

Note: `%TEMP%` can be cleaned by Windows or by you. Change `$TempFolderPath` in the script if the
history and the shortcuts should live somewhere permanent.

## Start at login

1. Press `WIN+R`, type `shell:startup`, press Enter.
2. Create a file `rss-feed-notifier.bat` in that folder with this content (adjust the path):

```bat
pwsh.exe -executionpolicy bypass -noninteractive -nologo -file "C:\path\to\rss-feed-notifier.ps1"
```

Use the variant without `-noninteractive` for the first start, so that you can answer the question
about installing the module.

## Troubleshooting

- **No notifications appear:** check that Windows notifications and "Focus assist / Do not disturb"
  allow them. Start the script in a console, it prints what it finds.
- **Buttons do nothing or the module throws errors:** replace `Microsoft.Toolkit.Uwp.Notifications.dll`
  in `$env:USERPROFILE\Documents\PowerShell\Modules\BurntToast\<version>\lib\` with a newer version
  (for example 7.1.3) from
  [NuGet](https://www.nuget.org/packages/Microsoft.Toolkit.Uwp.Notifications).
- **Nothing is found in a feed:** the script reads RSS 1.0/2.0 and Atom. The console shows a warning
  if a feed has no item nodes.

## Status

A small private tool, shared as is. It is not actively developed.
