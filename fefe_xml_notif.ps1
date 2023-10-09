# This script is experimental. 

# This script is just for educational purposes

# I am not the owner of the blog https://blog.fefe.de
# Owner of the blog is Felix von Leitner (https://de.wikipedia.org/wiki/Fefes_Blog)

# Check if BurntToast module is installed, if not, install it
if (-not (Get-Module -Name BurntToast -ListAvailable)) {
    Write-Output "Installing BurntToast module..."
    Install-Module -Name BurntToast -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import the BurntToast module
Import-Module -Name BurntToast -Force

# Load the required assembly
Add-Type -AssemblyName PresentationFramework

# RSS feed URL, hopefully should work with all rss feeds...
$rssUrl = "https://blog.fefe.de/rss.xml"
# $rssUrl = "https://www.stern.de/feed/standard/all"

# Recheck rssUrl every x Seconds. Standard = 300 Seconds
# If within the 300 seconds two rss items are added, only the newest item will create a notification.
$recheckEverySeconds = 300

# Maximum number of item in the rss feed, which should be notified to the user.
# No Notification will be notified twice after the script has started.
# ToDo: Improve the script, so that the links which were notified are being saved every x seconds and loaded at scriptstart
$MaxNumberOfRSSItemsNotified = 3

# Define the URL of the image, will be downloaded once in a temp folder
$url = "https://blog.fefe.de/logo-gross.jpg"

# Remember last url to avoid multiple notifications
$global:lastURL = ""

# Set to $true if you want see further information
$debug = [bool]$false

########### DO NOT CHANGE ANYTHING BELOW THIS ################
if ($debug) { Write-Host("Script started") }

# Define the path to the temporary folder
$tempFolderPath = [System.IO.Path]::GetTempPath()

# Combine the URL filename with the temporary folder path to create the full file path
$filePath = Join-Path -Path $tempFolderPath -ChildPath (Split-Path -Path $url -Leaf)

# Check if the file already exists in the temporary folder
if (-not (Test-Path -Path $filePath)) {
    # File does not exist, download the image
    Invoke-WebRequest -Uri $url -OutFile $filePath

    # Output a message indicating successful download
    if ($debug) { Write-Output "Image downloaded and saved to: $filePath" }
}
else {
    # File already exists, output a message indicating that the file was not downloaded
    if ($debug) { Write-Output "File already exists in the temporary folder: $filePath" }
}


function Get-NLatestRssItem {
    param (
        [int]$n = 1
    )
    $erg = @()
    $rss = Invoke-RestMethod -Uri $rssUrl
    # $rss
    for($i=0; $i -lt $n;$i++){
        $i
        if ($rss[$i]) {
            $erg+=[PSCustomObject]@{
                title = ($rss[$i]).title
                link = ($rss[$i]).link
                guid = ($rss[$i]).guid
            }
        }
    }
    return $erg
}


# Function to display a notification with the latest RSS item
function Show-RssNotification {
    param (
        [string]$title,
        [string]$subtext,
        [string]$link,
        [string]$toastAppLogoSourcePath
    )
    $Text1 = New-BTText -Content $title
    $Text2 = New-BTText -Content $subtext
    $toastAppLogo = New-Object Microsoft.Toolkit.Uwp.Notifications.ToastGenericAppLogo
    $toastAppLogo.Source = $toastAppLogoSourcePath
    $Binding1 = New-BTBinding -Children $Text1, $Text2 -AppLogoOverride $toastAppLogo
    $Visual1 = New-BTVisual -BindingGeneric $Binding1
    $Content1 = New-BTContent -Visual $Visual1 -Launch $link -ActivationType Protocol
    Submit-BTNotification -Content $Content1
}

# Main loop to send notifications with the latest RSS item
$notified = @()
while ($true) {
    try {
        $RssItems = Get-NLatestRssItem -n $MaxNumberOfRSSItemsNotified
        foreach($rssItem in $RssItems){
            if(($rssItem.link -notin $notified) -and ($rssItem.link -ne $null)) {
                # notify
                $title_length = ($rssItem.title.Length,30| Measure-Object -Minimum).Minimum
                $subtext_length = ($rssItem.title.Length,140| Measure-Object -Minimum).Minimum          
                Show-RssNotification -title $rssItem.title.SubString(0, $title_length) -subtext $rssItem.title.SubString(0, $subtext_length) -link $rssItem.link -toastAppLogoSourcePath $filePath
                $notified += $rssItem.link
            } else {
                # do not notify
                if ($debug) { Write-Host (($rssItem.link) +" was already notified.") }else { Write-Host(".") -NoNewLine }
            }
        }

        Start-Sleep -Seconds $recheckEverySeconds  # Check for new content every 5 minutes
    }
    catch {
        Write-Host "An error occurred: $_"
        Start-Sleep -Seconds 60  # Wait for a minute before retrying in case of an error
    }
}

