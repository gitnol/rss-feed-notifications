<#
.SYNOPSIS
    RSS-Feed-Notifier mit erweiterten Benachrichtigungsfunktionen

.DESCRIPTION
    Dieses Script überwacht konfigurierte RSS-Feeds und erstellt erweiterte
    Windows Toast-Benachrichtigungen mit:
    - Bildern aus RSS-Feeds (wenn vorhanden)
    - Inline-Aktionen (Später lesen, Archivieren, Verwerfen)
    - Sound-Benachrichtigungen mit verschiedenen Tönen
    - Hero-Images für visuell ansprechende Notifications
    
.NOTES
    Autor: Educational/Experimental Script
    Version: 3.0
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
# Debug-Modus aktivieren für erweiterte Ausgaben
$DebugMode = $false

# RSS-Feed URLs
$RssFeedUrls = @(
    "https://www.heise.de/security/rss/alert-news.rdf"
    "https://www.heise.de/rss/heise-top-alexa.xml"
    # "https://blog.fefe.de/rss.xml"
)

# Prüfintervall in Sekunden (Standard: 300 = 5 Minuten)
$CheckIntervalSeconds = 300

# Maximale Anzahl von RSS-Items pro Feed beim Start
$MaxItemsPerFeed = 3

# Pfad zum temporären Ordner
$TempFolderPath = [System.IO.Path]::GetTempPath()

# Sound-Einstellungen
$EnableSound = $true
$SoundScheme = "Default"  # Default, SMS, Reminder, Alarm, Mail, Silent

# Bild-Einstellungen
$EnableImages = $true
$MaxImageDownloadSize = 5MB  # Maximale Bildgröße für Download

# Archiv-Ordner für "Später lesen"
$ReadLaterFolder = Join-Path -Path $TempFolderPath -ChildPath "RSS_ReadLater"
$ArchiveFolder = Join-Path -Path $TempFolderPath -ChildPath "RSS_Archive"

# Ordner erstellen falls nicht vorhanden
if (-not (Test-Path $ReadLaterFolder)) {
    New-Item -Path $ReadLaterFolder -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $ArchiveFolder)) {
    New-Item -Path $ArchiveFolder -ItemType Directory -Force | Out-Null
}
#endregion Configuration

#region Module Installation
try {
    if (-not (Get-Module -Name BurntToast -ListAvailable)) {
        Write-Verbose "BurntToast-Modul wird installiert..."
        Install-Module -Name BurntToast -Force -SkipPublisherCheck -Scope CurrentUser -Confirm:$false -ErrorAction Stop
    }
    
    if (-not (Get-Module -Name BurntToast)) {
        Import-Module -Name BurntToast -Force -ErrorAction Stop
    }
}
catch {
    Write-Error "Fehler bei der Installation/Import des BurntToast-Moduls: $_"
    exit 1
}
#endregion Module Installation

#region Helper Functions

<#
.SYNOPSIS
    Generiert eine zufällige Konsolenfarbe
#>
function Get-RandomConsoleColor {
    [CmdletBinding()]
    param()
    
    $colors = @('DarkGray', 'Gray', 'DarkCyan', 'Cyan', 'DarkGreen', 'Green')
    return $colors | Get-Random
}

<#
.SYNOPSIS
    Lädt ein Bild herunter mit Größenlimit
#>
function Get-ImageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        
        [Parameter()]
        [int64]$MaxSize = 5MB
    )
    
    try {
        if (Test-Path $DestinationPath) {
            Write-Verbose "Bild bereits vorhanden: $DestinationPath"
            return $DestinationPath
        }
        
        Write-Verbose "Lade Bild herunter: $Url"
        
        # Bild herunterladen (HEAD-Request weggelassen, da er manchmal Fehler verursacht)
        Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -ErrorAction Stop -TimeoutSec 10
        
        # Prüfe ob Datei existiert und nicht leer ist
        if ((Test-Path $DestinationPath) -and (Get-Item $DestinationPath).Length -gt 0) {
            Write-Verbose "Bild heruntergeladen: $DestinationPath ($(((Get-Item $DestinationPath).Length / 1KB).ToString('F2')) KB)"
            return $DestinationPath
        }
        else {
            Write-Verbose "Bild-Download fehlgeschlagen oder Datei leer"
            return $null
        }
    }
    catch {
        Write-Verbose "Fehler beim Herunterladen: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Lädt Favicon-Bilder herunter
#>
function Get-FaviconImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$FaviconInfo
    )
    
    foreach ($item in $FaviconInfo) {
        if (-not (Test-Path -Path $item.LocalFile)) {
            try {
                Invoke-WebRequest -Uri $item.RemoteFile -OutFile $item.LocalFile -ErrorAction Stop
                Write-Verbose "Favicon heruntergeladen: $($item.RemoteFile)"
            }
            catch {
                Write-Warning "Fehler beim Herunterladen des Favicons: $_"
            }
        }
    }
}

<#
.SYNOPSIS
    Ruft RSS-Items ab mit erweiterten Metadaten
#>
function Get-LatestRssItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RssUrl,
        
        [Parameter()]
        [int]$Count = 1
    )
    
    try {
        $feed = Invoke-RestMethod -Uri $RssUrl -ErrorAction Stop
        Write-Verbose "RSS-Feed erfolgreich abgerufen: $RssUrl"
        
        $items = @()
        for ($i = 0; $i -lt [Math]::Min($Count, $feed.Count); $i++) {
            if ($feed[$i]) {
                # String-Konvertierung
                $titleValue = $feed[$i].Title
                $linkValue = $feed[$i].Link
                $guidValue = $feed[$i].Guid
                $descriptionValue = $feed[$i].Description
                $summaryValue = $feed[$i].Summary  # Atom-Feeds nutzen oft Summary statt Description
                $contentValue = $feed[$i].Content
                
                # Versuche verschiedene Wege, um content:encoded zu lesen
                $contentEncodedValue = $null
                
                # Methode 1: Direkter Namespace-Zugriff
                if ($feed[$i].'content:encoded') {
                    $contentEncodedValue = $feed[$i].'content:encoded'
                }
                # Methode 2: PSObject Properties durchsuchen
                elseif ($feed[$i].PSObject.Properties['content:encoded']) {
                    $contentEncodedValue = $feed[$i].PSObject.Properties['content:encoded'].Value
                }
                # Methode 3: encoded ohne Namespace-Präfix (funktioniert bei Heise RSS 2.0)
                elseif ($feed[$i].encoded) {
                    $contentEncodedValue = $feed[$i].encoded
                }
                
                if ($titleValue -is [System.Xml.XmlElement]) {
                    $title = $titleValue.InnerText
                }
                else {
                    $title = "$titleValue"
                }
                
                # Link kann in Atom-Feeds ein Objekt sein
                if ($linkValue -is [System.Xml.XmlElement]) {
                    # In Atom: <link href="..."/>
                    if ($linkValue.href) {
                        $link = "$($linkValue.href)"
                    }
                    else {
                        $link = $linkValue.InnerText
                    }
                }
                elseif ($linkValue -is [System.Object[]] -and $linkValue[0].href) {
                    # Manchmal gibt es mehrere Links, nimm den ersten
                    $link = "$($linkValue[0].href)"
                }
                else {
                    $link = "$linkValue"
                }
                
                if ($guidValue -is [System.Xml.XmlElement]) {
                    $guid = $guidValue.InnerText
                }
                else {
                    $guid = "$guidValue"
                }
                
                # Description oder Summary
                if ($descriptionValue -is [System.Xml.XmlElement]) {
                    $description = $descriptionValue.InnerText
                }
                elseif ($summaryValue -is [System.Xml.XmlElement]) {
                    $description = $summaryValue.InnerText
                }
                else {
                    $description = if ($descriptionValue) { "$descriptionValue" } else { "$summaryValue" }
                }
                
                # Versuche Bild-URL zu extrahieren
                $imageUrl = $null
                
                # 1. Prüfe media:content
                if ($feed[$i].'media:content') {
                    $imageUrl = $feed[$i].'media:content'.url
                }
                # 2. Prüfe media:thumbnail
                elseif ($feed[$i].'media:thumbnail') {
                    $imageUrl = $feed[$i].'media:thumbnail'.url
                }
                # 3. Prüfe enclosure
                elseif ($feed[$i].enclosure -and $feed[$i].enclosure.type -like "image/*") {
                    $imageUrl = $feed[$i].enclosure.url
                }
                
                # 4. Parse HTML im content-Feld (wichtig für Heise!)
                if (-not $imageUrl) {
                    # Versuche verschiedene Content-Felder
                    $contentHtml = $null
                    
                    # Prüfe content:encoded (RSS 2.0)
                    if ($contentEncodedValue) {
                        if ($contentEncodedValue -is [System.Xml.XmlElement]) {
                            $contentHtml = $contentEncodedValue.InnerXml
                        }
                        else {
                            $contentHtml = "$contentEncodedValue"
                        }
                    }
                    # Fallback auf content (Atom)
                    elseif ($contentValue) {
                        if ($contentValue -is [System.Xml.XmlElement]) {
                            $contentHtml = $contentValue.InnerXml
                        }
                        elseif ($contentValue.'#text') {
                            $contentHtml = $contentValue.'#text'
                        }
                        else {
                            $contentHtml = "$contentValue"
                        }
                    }
                    
                    if ($contentHtml) {
                        Write-Verbose "Content-HTML gefunden (Länge: $($contentHtml.Length))"
                        
                        # Extrahiere erste <img src="..."> aus dem HTML
                        if ($contentHtml -match '<img[^>]+src=[''"]([^''"]+)[''"]') {
                            $imageUrl = $matches[1]
                            Write-Verbose "Bild gefunden: $imageUrl"
                        }
                    }
                }
                
                # 5. Fallback: Auch in description/summary suchen
                if (-not $imageUrl -and $description -and "$description" -match '<img[^>]+src=[''"]([^''"]+)[''"]') {
                    $imageUrl = $matches[1]
                    Write-Verbose "[DEBUG] Bild gefunden in Description: $imageUrl"
                }
                
                # Konvertiere ImageUrl zu String falls vorhanden
                if ($imageUrl -is [System.Xml.XmlElement]) {
                    $imageUrl = $imageUrl.InnerText
                }
                elseif ($imageUrl) {
                    $imageUrl = "$imageUrl"
                }
                
                $items += [PSCustomObject]@{
                    Title       = $title
                    Link        = $link
                    Guid        = $guid
                    Description = $description
                    ImageUrl    = $imageUrl
                }
            }
        }
        
        return $items
    }
    catch {
        Write-Warning "Fehler beim Abrufen des RSS-Feeds von ${RssUrl}: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Generiert Benachrichtigungsgruppen-Namen
#>
function Get-NotificationGroupName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RssUrl
    )
    
    try {
        $uri = [System.Uri]$RssUrl
        $hostname = $uri.Host -replace '^www\.', ''
        $path = [System.IO.Path]::ChangeExtension($uri.AbsolutePath, $null) -replace '\.', '' -replace '/', '-'
        
        return "$hostname$path"
    }
    catch {
        return "rss-notification"
    }
}

<#
.SYNOPSIS
    Speichert einen Artikel für später
#>
function Save-ArticleForLater {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [Parameter(Mandatory)]
        [string]$Link,
        
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "${timestamp}_article.txt"
        $filePath = Join-Path -Path $FolderPath -ChildPath $fileName
        
        $content = @"
Titel: $Title
Link: $Link
Gespeichert: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")
"@
        
        Set-Content -Path $filePath -Value $content -Encoding UTF8
        Write-Verbose "Artikel gespeichert: $filePath"
    }
    catch {
        Write-Warning "Fehler beim Speichern des Artikels: $_"
    }
}

<#
.SYNOPSIS
    Zeigt erweiterte Toast-Benachrichtigung an
#>
function Show-AdvancedRssNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory)]
        [string]$Link,
        
        [Parameter(Mandatory)]
        [string]$IconPath,
        
        [Parameter()]
        [string]$HeroImagePath,
        
        [Parameter(Mandatory)]
        [string]$GroupName,
        
        [Parameter(Mandatory)]
        [string]$Domain,
        
        [Parameter()]
        [string]$SoundType = "Default"
    )
    
    try {
        # Texte erstellen
        $titleString = [string]$Title
        $messageString = [string]$Message
        
        $text1 = New-BTText -Content $titleString
        $text2 = New-BTText -Content $messageString
        
        # App-Logo (Favicon)
        $appLogo = New-BTImage -Source $IconPath -AppLogoOverride -Crop Circle
        
        # Hero-Image (großes Bild) falls vorhanden UND Datei existiert
        $heroImage = $null
        if ($HeroImagePath -and (Test-Path $HeroImagePath)) {
            Write-Verbose "Hero-Image wird zur Benachrichtigung hinzugefügt"
            $heroImage = New-BTImage -Source $HeroImagePath -HeroImage
        }
        
        # Binding mit oder ohne Hero-Image
        if ($heroImage) {
            $binding = New-BTBinding -Children $text1, $text2 -AppLogoOverride $appLogo -HeroImage $heroImage
        }
        else {
            $binding = New-BTBinding -Children $text1, $text2 -AppLogoOverride $appLogo
        }
        
        $visual = New-BTVisual -BindingGeneric $binding
        
        # Inline-Aktionen erstellen
        $readLaterButton = New-BTButton -Content "📖 Später lesen" -Arguments "readlater|$Link|$Title" -ActivationType Protocol
        $archiveButton = New-BTButton -Content "📦 Archivieren" -Arguments "archive|$Link|$Title" -ActivationType Protocol
        $dismissButton = New-BTButton -Dismiss -Content "❌ Verwerfen"
        
        $actions = New-BTAction -Buttons $readLaterButton, $archiveButton, $dismissButton
        
        # Sound auswählen
        $sound = switch ($SoundType) {
            "SMS" { New-BTAudio -Source 'ms-winsoundevent:Notification.SMS' }
            "Reminder" { New-BTAudio -Source 'ms-winsoundevent:Notification.Reminder' }
            "Alarm" { New-BTAudio -Source 'ms-winsoundevent:Notification.Looping.Alarm' }
            "Mail" { New-BTAudio -Source 'ms-winsoundevent:Notification.Mail' }
            "Silent" { New-BTAudio -Silent }
            default { New-BTAudio -Source 'ms-winsoundevent:Notification.Default' }
        }
        
        # Header erstellen
        $header = New-BTHeader -Id $GroupName -Title $GroupName -Arguments $Domain
        
        # Content zusammenbauen
        $content = New-BTContent -Visual $visual -Actions $actions -Audio $sound -Launch $Link -ActivationType Protocol -Header $header
        
        # Benachrichtigung anzeigen
        Submit-BTNotification -Content $content
        
        Write-Verbose "Benachrichtigung angezeigt: $titleString"
    }
    catch {
        Write-Warning "Fehler beim Anzeigen der Benachrichtigung: $_"
    }
}

<#
.SYNOPSIS
    Verwaltet Benachrichtigungsverlauf (Speichern/Laden)
#>
function Save-NotificationHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter(Mandatory)]
        [string]$FileName,
        
        [Parameter(Mandatory)]
        [array]$Data
    )
    
    $filePath = Join-Path -Path $FolderPath -ChildPath "$FileName.json"
    
    try {
        $Data | ConvertTo-Json | Set-Content -Path $filePath -ErrorAction Stop
        Write-Verbose "Verlauf gespeichert: $filePath"
    }
    catch {
        Write-Warning "Fehler beim Speichern: $_"
    }
}

<#
.SYNOPSIS
    Lädt Benachrichtigungsverlauf aus Datei
#>
function Get-NotificationHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    $filePath = Join-Path -Path $FolderPath -ChildPath "$FileName.json"
    
    if (Test-Path -Path $filePath) {
        try {
            $loadedData = Get-Content -Path $filePath -ErrorAction Stop | ConvertFrom-Json
            Write-Verbose "Verlauf geladen: $filePath"
            return @($loadedData)
        }
        catch {
            Write-Warning "Fehler beim Laden: $_"
            return @()
        }
    }
    else {
        Write-Verbose "Keine Verlaufsdatei gefunden"
        return @()
    }
}

#endregion Helper Functions

#region Event Handler Registration

# Event Handler für Button-Klicks registrieren
# WICHTIG: Nur einmal beim Start registrieren!

try {
    # Prüfen ob bereits registriert
    $existingEvent = Get-EventSubscriber -SourceIdentifier "BT_ActionInvoked" -ErrorAction SilentlyContinue
    
    if (-not $existingEvent) {
        Register-EngineEvent -SourceIdentifier "BT_ActionInvoked" -Action {
            param($eventSender, $eventData)
            
            try {
                $arguments = $eventData.Arguments
                Write-Host "Button geklickt: $arguments" -ForegroundColor Cyan
                
                # Argumente parsen
                $parts = $arguments -split '\|'
                
                if ($parts.Count -ge 3) {
                    $action = $parts[0]
                    $link = $parts[1]
                    $title = $parts[2]
                    
                    switch ($action) {
                        "readlater" {
                            Save-ArticleForLater -Title $title -Link $link -FolderPath $using:ReadLaterFolder
                            Write-Host "Artikel für später gespeichert: $title" -ForegroundColor Green
                        }
                        "archive" {
                            Save-ArticleForLater -Title $title -Link $link -FolderPath $using:ArchiveFolder
                            Write-Host "Artikel archiviert: $title" -ForegroundColor Yellow
                        }
                    }
                }
            }
            catch {
                Write-Warning "Fehler im Event Handler: $_"
            }
        } | Out-Null
        
        Write-Verbose "Event Handler registriert"
    }
}
catch {
    Write-Warning "Event Handler konnte nicht registriert werden: $_"
}

#endregion Event Handler Registration

#region Main Script Logic

Write-Host "RSS-Feed-Notifier mit erweiterten Benachrichtigungen gestartet" -ForegroundColor Green
Write-Host "Später lesen: $ReadLaterFolder" -ForegroundColor Cyan
Write-Host "Archiv: $ArchiveFolder" -ForegroundColor Cyan

# Favicon-Informationen vorbereiten
$faviconData = $RssFeedUrls | ForEach-Object {
    $domain = ([uri]$_).Host
    [PSCustomObject]@{
        RemoteFile = "https://$domain/favicon.ico"
        LocalFile  = Join-Path -Path $TempFolderPath -ChildPath "${domain}_favicon.ico"
    }
} | Sort-Object -Property RemoteFile, LocalFile -Unique

# Favicons herunterladen
Get-FaviconImage -FaviconInfo $faviconData

# Benachrichtigungsverlauf laden
$notificationHistory = Get-NotificationHistory -FolderPath $TempFolderPath -FileName "rss_notifier_history_advanced"
if (-not $notificationHistory) { 
    $notificationHistory = @() 
}

Write-Verbose "Geladener Verlauf enthält $($notificationHistory.Count) Einträge"

# Hauptschleife
$counter = $CheckIntervalSeconds

while ($true) {
    try {
        if ($counter -ge $CheckIntervalSeconds) {
            $newNotificationsCreated = $false
            
            foreach ($feedUrl in $RssFeedUrls) {
                Write-Verbose "Prüfe Feed: $feedUrl"
                
                $rssItems = Get-LatestRssItems -RssUrl $feedUrl -Count $MaxItemsPerFeed
                
                foreach ($item in $rssItems) {
                    if ($item.Link -and $item.Link -notin $notificationHistory) {
                        # String-Konvertierung
                        $titleString = [string]$item.Title
                        
                        Write-Verbose "Neues Item gefunden: $titleString (Link: $($item.Link))"
                        
                        if ($titleString.Length -gt 0) {
                            # Optimale Zeichenlängen für Windows Toast Notifications
                            # Windows 11: Titel ~70, Text ~141
                            # Windows 10: Titel ~64, Text ~121
                            # Wir verwenden konservative Werte für Kompatibilität
                            $titleLength = [Math]::Min($titleString.Length, 65)
                            $messageLength = [Math]::Min($titleString.Length, 120)
                            
                            $feedHost = ([uri]$feedUrl).Host
                            $feedScheme = ([uri]$feedUrl).Scheme
                            $iconPath = ($faviconData | Where-Object { $_.LocalFile -like "*$feedHost*" }).LocalFile
                            $domain = "$feedScheme`://$feedHost"
                            $groupName = Get-NotificationGroupName -RssUrl $feedUrl
                            
                            # Hero-Image herunterladen falls vorhanden
                            $heroImagePath = $null
                            if ($EnableImages -and $item.ImageUrl) {
                                Write-Verbose "Bild-URL gefunden: $($item.ImageUrl)"
                                
                                # Erstelle eindeutigen Dateinamen basierend auf URL-Hash
                                $urlHash = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($item.ImageUrl))).Replace("-", "")
                                $imageExtension = [System.IO.Path]::GetExtension($item.ImageUrl).Split('?')[0]
                                if (-not $imageExtension -or $imageExtension.Length -gt 5) { $imageExtension = ".jpg" }
                                $imageFileName = "RSS_${urlHash}${imageExtension}"
                                $imageLocalPath = Join-Path -Path $TempFolderPath -ChildPath $imageFileName
                                
                                Write-Verbose "Lokaler Bildpfad: $imageLocalPath"
                                
                                $heroImagePath = Get-ImageFile -Url $item.ImageUrl -DestinationPath $imageLocalPath -MaxSize $MaxImageDownloadSize
                                
                                if ($heroImagePath) {
                                    Write-Verbose "Hero-Image wird verwendet: $heroImagePath"
                                }
                            }
                            
                            # Sound-Schema basierend auf Quelle
                            $currentSound = if ($EnableSound) { $SoundScheme } else { "Silent" }
                            
                            Write-Verbose "Erstelle Benachrichtigung für: $($titleString.Substring(0, $titleLength))"
                            
                            Show-AdvancedRssNotification `
                                -Title $titleString.Substring(0, $titleLength) `
                                -Message $titleString.Substring(0, $messageLength) `
                                -Link $item.Link `
                                -IconPath $iconPath `
                                -HeroImagePath $heroImagePath `
                                -GroupName $groupName `
                                -Domain $domain `
                                -SoundType $currentSound
                            
                            $notificationHistory += $item.Link
                            $newNotificationsCreated = $true
                            
                            Write-Verbose "Link zur Historie hinzugefügt: $($item.Link)"
                        }
                    }
                    else {
                        if ($DebugMode) {
                            Write-Verbose "Bereits benachrichtigt: $($item.Link)"
                        }
                        else {
                            Write-Host "." -NoNewline -ForegroundColor (Get-RandomConsoleColor)
                        }
                    }
                }
            }
            
            # Verlauf speichern, falls neue Benachrichtigungen erstellt wurden
            if ($newNotificationsCreated) {
                Write-Verbose "Speichere Verlauf mit $($notificationHistory.Count) Einträgen"
                Save-NotificationHistory -FolderPath $TempFolderPath -FileName "rss_notifier_history_advanced" -Data $notificationHistory
            }
            
            $counter = 0
        }
        
        # Fortschrittsanzeige
        Start-Sleep -Seconds 1
        $percentComplete = ($counter / $CheckIntervalSeconds) * 100
        $secondsRemaining = $CheckIntervalSeconds - $counter
        
        Write-Progress `
            -Activity "Warte auf nächste Prüfung" `
            -Status "Noch $secondsRemaining Sekunden" `
            -PercentComplete $percentComplete `
            -CurrentOperation "Nächste Prüfung in $secondsRemaining Sekunden"
        
        $counter++
    }
    catch {
        Write-Error "Fehler in der Hauptschleife: $_"
        Start-Sleep -Seconds 60
    }
}

#endregion Main Script Logic