<#
.SYNOPSIS
    RSS-Feed-Notifier mit erweiterten Benachrichtigungsfunktionen (Sequenzielle Version)

.DESCRIPTION
    Dieses Script überwacht konfigurierte RSS-Feeds nacheinander (sequenziell) 
    und erstellt erweiterte Windows Toast-Benachrichtigungen.
    
.NOTES
    Autor: Educational/Experimental Script
    Version: 5.1 (Final)
    Voraussetzungen: 
    - Windows 10/11
    - PowerShell 5.1 oder höher
    - BurntToast-Modul (wird automatisch installiert)

.LINK
    https://github.com/Windos/BurntToast
#>

[CmdletBinding()]
param()

#Requires -Version 5.1

#region Configuration
$RssFeedUrls = @(
    "https://www.heise.de/security/feed.xml",
        "https://www.heise.de/security/Alerts/feed.xml",
        "https://www.heise.de/rss/heise-top-atom.xml",
        "https://www.stern.de/feed/standard/all"
)
$CheckIntervalSeconds = 300
$MaxItemsPerFeed = 5
$TempFolderPath = [System.IO.Path]::GetTempPath()
$EnableSound = $true
$SoundScheme = "Default"
$EnableImages = $true
$MaxImageDownloadSize = 5MB
$ReadLaterFolder = Join-Path -Path $TempFolderPath -ChildPath "RSS_ReadLater"
$ArchiveFolder = Join-Path -Path $TempFolderPath -ChildPath "RSS_Archive"
$MaxHistoryItems = 200
$ImageCacheDays = 7

if (-not (Test-Path $ReadLaterFolder)) { New-Item -Path $ReadLaterFolder -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $ArchiveFolder)) { New-Item -Path $ArchiveFolder -ItemType Directory -Force | Out-Null }
#endregion

#region Module Installation
try {
    if (-not (Get-Module -Name BurntToast -ListAvailable)) {
        Write-Verbose "BurntToast-Modul wird installiert..."
        Install-Module -Name BurntToast -Force -SkipPublisherCheck -Scope CurrentUser -Confirm:$false -ErrorAction Stop
    }
    Import-Module -Name BurntToast -Force -ErrorAction Stop
}
catch { Write-Error "Fehler bei der Installation/Import des BurntToast-Moduls: $_"; exit 1 }
#endregion

#region Helper Functions
function Get-RandomConsoleColor {
    @('DarkGray', 'Gray', 'DarkCyan', 'Cyan', 'DarkGreen', 'Green') | Get-Random
}

function Get-ImageFile {
    param([string]$Url, [string]$DestinationPath, [int64]$MaxSize = 5MB)
    try {
        if (Test-Path $DestinationPath) { return $DestinationPath }
        Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -ErrorAction Stop -TimeoutSec 10
        if ((Test-Path $DestinationPath) -and (Get-Item $DestinationPath).Length -gt 0) { return $DestinationPath }
        return $null
    }
    catch { return $null }
}

function Get-FaviconImage {
    param([PSCustomObject[]]$FaviconInfo)
    foreach ($item in $FaviconInfo) {
        if (-not (Test-Path -Path $item.LocalFile)) {
            try { Invoke-WebRequest -Uri $item.RemoteFile -OutFile $item.LocalFile -ErrorAction Stop }
            catch { Write-Warning "Fehler beim Herunterladen des Favicons für $($item.RemoteFile): $_" }
        }
    }
}

function Get-LatestRssItems {
    param(
        [Parameter(Mandatory)] [string]$RssUrl,
        [Parameter()] [int]$Count = 5
    )
    try {
        $response = Invoke-WebRequest -Uri $RssUrl -UserAgent "PowerShell RSS Notifier" -ErrorAction Stop
        $xml = [xml]$response.Content
        $items = @()
        $nsmgr = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
        $nsmgr.AddNamespace('rss', 'http://purl.org/rss/1.0/')
        $nsmgr.AddNamespace('atom', 'http://www.w3.org/2005/Atom')
        $nsmgr.AddNamespace('media', 'http://search.yahoo.com/mrss/')
        $nsmgr.AddNamespace('content', 'http://purl.org/rss/1.0/modules/content/')
        
        $itemNodes = $xml.SelectNodes('//rss:item | //item | //atom:entry', $nsmgr)
        if ($itemNodes.Count -eq 0) {
            Write-Warning "Konnte keine Artikel-Knoten im Feed von '$RssUrl' finden."
            return @()
        }
        
        for ($i = 0; $i -lt [Math]::Min($Count, $itemNodes.Count); $i++) {
            $node = $itemNodes[$i]
            
            # --- FINALE KORREKTUR START ---
            $titleNode = $node.SelectSingleNode('rss:title | title | atom:title', $nsmgr)
            $title = $titleNode.InnerText ?? $titleNode.'#text'
            
            # Robuste Link-Extraktion: Priorisiert das 'href'-Attribut (für Atom)
            # und fällt auf den inneren Text zurück (für RSS).
            $linkNode = $node.SelectSingleNode('rss:link | link | atom:link[@rel="alternate"] | atom:link', $nsmgr)
            $link = $linkNode.href 
            if ([string]::IsNullOrWhiteSpace($link)) {
                $link = $linkNode.InnerText ?? $linkNode.'#text'
            }

            $descriptionNode = $node.SelectSingleNode('rss:description | description | atom:summary', $nsmgr)
            $description = $descriptionNode.InnerText ?? $descriptionNode.'#text'
            
            # Robuste Bild-Extraktion: Sucht an mehreren Stellen.
            $imageUrl = ($node.SelectSingleNode('enclosure[@type="image/jpeg"] | media:content', $nsmgr)).url
            if (-not $imageUrl) {
                # Sucht jetzt auch im allgemeinen <content>-Tag nach einem <img>
                $contentNode = $node.SelectSingleNode('content:encoded | atom:content', $nsmgr)
                $contentHtml = $contentNode.'#cdata-section' ?? $contentNode.InnerXml ?? $contentNode.'#text'
                if ($contentHtml -match '<img[^>]+src="([^"]+)"') { $imageUrl = $matches[1] }
            }
            # --- FINALE KORREKTUR ENDE ---
            
            $items += [PSCustomObject]@{ Title = [string]$title; Link = [string]$link; Description = [string]$description; ImageUrl = [string]$imageUrl }
        }
        return $items
    }
    catch {
        Write-Warning "Fehler beim Verarbeiten des RSS-Feeds von ${RssUrl}: $_"
        return @()
    }
}

function Get-NotificationGroupName {
    param([string]$RssUrl)
    try {
        $uri = [System.Uri]$RssUrl
        $hostname = $uri.Host -replace '^www\.', ''
        $path = [System.IO.Path]::ChangeExtension($uri.AbsolutePath, $null) -replace '\.', '' -replace '/', '-'
        return "$hostname$path"
    }
    catch { return "rss-notification" }
}

function Save-ArticleForLater {
    param([string]$Title, [string]$Link, [string]$FolderPath)
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $safeTitle = $Title -replace '[\\/:*?"<>|]', ''
        $fileName = "${timestamp}_$($safeTitle.Substring(0, [Math]::Min(30, $safeTitle.Length))).url"
        $filePath = Join-Path -Path $FolderPath -ChildPath $fileName
        $content = "[InternetShortcut]`nURL=$Link"
        Set-Content -Path $filePath -Value $content -Encoding UTF8
    }
    catch { Write-Warning "Fehler beim Speichern des Artikels: $_" }
}

function Show-AdvancedRssNotification {
    param([string]$Title, [string]$Message, [string]$Link, [string]$IconPath, [string]$HeroImagePath, [string]$GroupName, [string]$SoundType)
    try {
        $text1 = New-BTText -Content $Title; $text2 = New-BTText -Content $Message
        $appLogo = if ($IconPath -and (Test-Path $IconPath)) { New-BTImage -Source $IconPath -AppLogoOverride -Crop Circle } else { New-BTImage -Source 'shell32.dll,219' -AppLogoOverride -Crop Circle }
        $heroImage = if ($EnableImages -and $HeroImagePath -and (Test-Path $HeroImagePath)) { New-BTImage -Source $HeroImagePath -HeroImage } else { $null }
        $binding = if ($heroImage) { New-BTBinding -Children $text1, $text2 -AppLogoOverride $appLogo -HeroImage $heroImage } else { New-BTBinding -Children $text1, $text2 -AppLogoOverride $appLogo }
        $visual = New-BTVisual -BindingGeneric $binding
        $readLaterButton = New-BTButton -Content "📖 Später lesen" -Arguments "readlater|$Link|$Title"
        $archiveButton = New-BTButton -Content "📦 Archivieren" -Arguments "archive|$Link|$Title"
        $dismissButton = New-BTButton -Dismiss -Content "❌ Verwerfen"
        $actions = New-BTAction -Buttons $readLaterButton, $archiveButton, $dismissButton
        $sound = switch ($SoundType) {
            "SMS" { New-BTAudio -Source 'ms-winsoundevent:Notification.SMS' } "Reminder" { New-BTAudio -Source 'ms-winsoundevent:Notification.Reminder' } "Alarm" { New-BTAudio -Source 'ms-winsoundevent:Notification.Looping.Alarm' } "Mail" { New-BTAudio -Source 'ms-winsoundevent:Notification.Mail' } "Silent" { New-BTAudio -Silent }
            default { New-BTAudio -Source 'ms-winsoundevent:Notification.Default' }
        }
        $header = New-BTHeader -Id $GroupName -Title $GroupName -Arguments $Link
        $content = New-BTContent -Visual $visual -Actions $actions -Audio $sound -Launch $Link -ActivationType Protocol -Header $header
        Submit-BTNotification -Content $content
    }
    catch { Write-Warning "Fehler beim Anzeigen der Benachrichtigung für '$Title': $_" }
}

function Save-NotificationHistory {
    param([string]$FilePath, [hashtable]$HistoryHashtable)
    try {
        $saveObject = @{}
        foreach ($key in $HistoryHashtable.Keys) { $saveObject[$key] = [System.Collections.Generic.List[string]]($HistoryHashtable[$key]) }
        $saveObject | ConvertTo-Json -Depth 3 | Set-Content -Path $FilePath -Encoding UTF8
    }
    catch { Write-Warning "Fehler beim Speichern des Verlaufs: $_" }
}

function Get-NotificationHistory {
    param([string]$FilePath)
    $historyHashtable = [hashtable]::new()
    if (Test-Path $FilePath) {
        Write-Verbose "Lade Verlaufsdatei von '$FilePath'"
        try {
            $jsonData = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
            foreach ($key in $jsonData.PSObject.Properties.Name) {
                $historyHashtable[$key] = [System.Collections.Generic.HashSet[string]]::new([string[]]$jsonData.$key, [System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        catch { Write-Warning "Fehler beim Laden der Verlaufsdatei '$FilePath': $_" }
    }
    return $historyHashtable
}

function Remove-OldCacheFiles {
    param([string]$FolderPath, [int]$MaxAgeDays)
    try {
        $cleanupThreshold = (Get-Date).AddDays(-$MaxAgeDays)
        Get-ChildItem -Path $FolderPath -Filter "RSS_*.jpg" -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cleanupThreshold } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch { Write-Warning "Fehler bei der Bereinigung der Cache-Dateien: $_" }
}
#endregion

#region Event Handler
try {
    if (-not (Get-EventSubscriber -SourceIdentifier "BT_ActionInvoked" -ErrorAction SilentlyContinue)) {
        Register-EngineEvent -SourceIdentifier "BT_ActionInvoked" -Action {
            try {
                $arguments = $event.SourceEventArgs.Arguments; $parts = $arguments -split '\|'
                if ($parts.Count -ge 3) {
                    $action, $link, $title = $parts
                    switch ($action) {
                        "readlater" { Save-ArticleForLater -Title $title -Link $link -FolderPath $using:ReadLaterFolder }
                        "archive" { Save-ArticleForLater -Title $title -Link $link -FolderPath $using:ArchiveFolder }
                    }
                }
            }
            catch { Write-Warning "Fehler im Event Handler: $_" }
        } | Out-Null
    }
}
catch { Write-Warning "Event Handler konnte nicht registriert werden: $_" }
#endregion

#region Main Script Logic
Write-Host "RSS-Feed-Notifier v5.1 (Final) gestartet" -ForegroundColor Green
$faviconData = $RssFeedUrls | ForEach-Object { $domain = ([uri]$_).Host; [PSCustomObject]@{ Url = $_; RemoteFile = "https://$domain/favicon.ico"; LocalFile = Join-Path -Path $TempFolderPath -ChildPath "${domain}_favicon.ico" } } | Sort-Object -Property RemoteFile -Unique
Get-FaviconImage -FaviconInfo $faviconData
$historyFilePath = Join-Path -Path $TempFolderPath -ChildPath "rss_notifier_history_v5.json"
$notificationHistory = Get-NotificationHistory -FilePath $historyFilePath
$counter = $CheckIntervalSeconds
$cleanupCounter = 0

while ($true) {
    try {
        if ($counter -ge $CheckIntervalSeconds) {
            Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - Prüfe RSS-Feeds..." -ForegroundColor Yellow
            $newNotificationsCreated = $false

            foreach ($feedUrl in $RssFeedUrls) {
                $groupName = Get-NotificationGroupName -RssUrl $feedUrl
                $rssItems = Get-LatestRssItems -RssUrl $feedUrl -Count $MaxItemsPerFeed
                Write-Verbose "Verarbeite Feed: $feedUrl mit Gruppe: $groupName"

                if ($rssItems.Count -eq 0) {
                    Write-Host "Keine Artikel im Feed gefunden." -ForegroundColor Gray; continue 
                }
                else { 
                    Write-Host "Gefundene Artikel: $($rssItems.Count)" -ForegroundColor Gray 
                }
                Write-Verbose "Verarbeite Feed: $feedUrl mit Gruppe: $groupName"
                if ($rssItems.Count -eq 0) {
                    Write-Host "Keine Artikel im Feed gefunden." -ForegroundColor Gray; continue 
                }
                else { 
                    Write-Host "Gefundene Artikel: $($rssItems.Count)" -ForegroundColor Gray 
                }
                if (-not $notificationHistory.ContainsKey($groupName)) { $notificationHistory[$groupName] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
                $feedHistory = $notificationHistory[$groupName]

                foreach ($item in $rssItems) {
                    Write-Host ($item | ConvertTo-Json -Depth 3) -ForegroundColor Cyan

                    if ($item.Link -and -not $feedHistory.Contains($item.Link)) {
                        $newNotificationsCreated = $true
                        $titleString = [string]$item.Title
                        # Hole die Beschreibung und entferne HTML-Tags für eine saubere Anzeige
                        $descriptionString = [string]$item.Description -replace '<.*?>' | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_) }

                        if ([string]::IsNullOrWhiteSpace($titleString)) { continue }

                        Write-Host "Neuer Artikel: $titleString" -ForegroundColor Green

                        # Definiere die maximale Länge für Titel und die Nachrichten-Vorschau
                        $titleLength = [Math]::Min($titleString.Length, 70)
                        $messageLength = [Math]::Min($descriptionString.Length, 150)
                        $iconPath = ($faviconData | Where-Object { $_.Url -eq $feedUrl }).LocalFile
                        
                        $heroImagePath = $null
                        if ($EnableImages -and $item.ImageUrl) {
                            $urlHash = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($item.ImageUrl))).Replace("-", "")
                            $imageExtension = ([System.IO.Path]::GetExtension($item.ImageUrl).Split('?')[0]); if (-not $imageExtension -or $imageExtension.Length -gt 5) { $imageExtension = ".jpg" }
                            $imageFileName = "RSS_${urlHash}${imageExtension}"
                            $imageLocalPath = Join-Path -Path $TempFolderPath -ChildPath $imageFileName
                            $heroImagePath = Get-ImageFile -Url $item.ImageUrl -DestinationPath $imageLocalPath -MaxSize $MaxImageDownloadSize
                        }
                        
                        $currentSound = if ($EnableSound) { $SoundScheme } else { "Silent" }
                        
                        Show-AdvancedRssNotification `
                            -Title $titleString.Substring(0, $titleLength) `
                            -Message $descriptionString.Substring(0, $messageLength) `
                            -Link $item.Link `
                            -IconPath $iconPath `
                            -HeroImagePath $heroImagePath `
                            -GroupName $groupName `
                            -SoundType $currentSound

                        [void]$feedHistory.Add($item.Link)
                    }
                    else { Write-Host "." -NoNewline -ForegroundColor (Get-RandomConsoleColor) }
                }
                while ($feedHistory.Count -gt $MaxHistoryItems) { $oldestLink = $feedHistory | Select-Object -First 1; [void]$feedHistory.Remove($oldestLink) }
            }
            if ($newNotificationsCreated) { Save-NotificationHistory -FilePath $historyFilePath -HistoryHashtable $notificationHistory } 
            else { Write-Host " Keine neuen Artikel." -ForegroundColor Gray }
            $counter = 0
        }
        if ($cleanupCounter % 3600 -eq 0) { Remove-OldCacheFiles -FolderPath $TempFolderPath -MaxAgeDays $ImageCacheDays }

        $secondsRemaining = $CheckIntervalSeconds - $counter
        Write-Progress -Activity "RSS-Feed Notifier läuft" -Status "Nächste Prüfung in $secondsRemaining Sek." -PercentComplete (($counter / $CheckIntervalSeconds) * 100)
        
        Start-Sleep -Seconds 1
        $counter++; $cleanupCounter++
    }
    catch { Write-Error "Unerwarteter Fehler in der Hauptschleife: $_"; Start-Sleep -Seconds 60 }
}
#endregion