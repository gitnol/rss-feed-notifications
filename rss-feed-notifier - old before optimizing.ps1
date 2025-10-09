# This script is just for educational purposes. It is functional, but experimental

# I am not the owner of the blog https://blog.fefe.de
# Owner of the blog is Felix von Leitner (https://de.wikipedia.org/wiki/Fefes_Blog)



try {
    # Check if BurntToast module is installed, if not, install it
    if (-not (Get-Module -Name BurntToast -ListAvailable)) {
        Write-Host "Installing BurntToast module..."
        Install-Module -Name BurntToast -Force -SkipPublisherCheck -Scope CurrentUser -Confirm:$false
    }
    # Import the BurntToast module  --> uncomment it, if add-type below is not functioning.
    # Import-Module -Name BurntToast -Force
    # if you get the error "WinRT.Runtime.dll: Assembly with same name is already loaded" try to uncomment it.
    # A newer Version is present and the PresentationFrameWork can be loaded.
    # With the following command you see, which assemblies are currently loaded and where they are located
    # [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object Location | Sort-Object -Property FullName | Select-Object -Property FullName, Location, GlobalAssemblyCache, IsFullyTrusted | Out-GridView    
}
catch {
    Write-Error "An Error occured :("
}

# Load the required assembly
Add-Type -AssemblyName PresentationFramework

# Set to $true if you want see further information
$debug = [bool]$false

# RSS feed URL, hopefully should work with all rss feeds... at least one rss feed should be provided
$ArrayOfrssUrls = @()
# $ArrayOfrssUrls += "https://blog.fefe.de/rss.xml"
# $ArrayOfrssUrls += "https://www.stern.de/feed/standard/all"
# $ArrayOfrssUrls += "https://www.heise.de/security/rss/news.rdf"
$ArrayOfrssUrls += "https://www.heise.de/security/rss/alert-news.rdf"
$ArrayOfrssUrls += "https://www.heise.de/rss/heise-top-alexa.xml"

# Recheck rssUrl every x Seconds. Standard = 300 Seconds
# If within the 300 seconds two rss items are added, only the newest item will create a notification.
$recheckEverySeconds = 300

# Maximum number of item in each rss feed, which should be notified to the user.
# No Notification will be notified twice after the script has started.
$MaxNumberOfRSSItemsNotified = 3

########### DO NOT CHANGE ANYTHING BELOW THIS ################
if ($debug) { Write-Host("Script started") }

# Define the path to the temporary folder
$tempFolderPath = [System.IO.Path]::GetTempPath()

# Function to generate a random foreground color
Function Get-RandomColor {
    $colors = "Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", "DarkYellow", "Gray","DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White"
    return $colors[(Get-Random -Minimum 0 -Maximum $colors.Length)]
}

function Download-Image {
    param (
        $faviconInfos,
        [bool]$debug = $false
    )

    foreach($item in $faviconInfos) {
        # Check if the file already exists in the temporary folder
        $filePath = $item.localfile
        $url = $item.remotefile
        if (-not (Test-Path -Path $filePath)) {
            # File does not exist, download the image
            Invoke-WebRequest -Uri $url -OutFile $filePath

            # Output a message indicating successful download
            if ($debug) { Write-Host "Image downloaded and saved to: $filePath" }
        } else {
            # File already exists, output a message indicating that the file was not downloaded
            if ($debug) { Write-Host "File already exists in the temporary folder: $filePath" }
        }
    }
}

function Get-NLatestRssItem {
    param (
        [int]$n = 1,
        [string]$myRSSUrl
    )
    $erg = @()
    # Try-Catch wrapping around this messy little thing
    if ($myRSSUrl) {
        $rss = Invoke-RestMethod -Uri $myRSSUrl
        If ($debug) { $rss }
        for ($i = 0; $i -lt $n; $i++) {
            # $i # commented, because it leads to an error if you throw something in the powershell pipeline :(
            if ($rss[$i]) {
                $erg += [PSCustomObject]@{
                    title = ($rss[$i]).title
                    link  = ($rss[$i]).link
                    guid  = ($rss[$i]).guid
                }
            }
        }
    }
    return $erg
}

function Get-NotificationGroup {
    param (
        [string]$rssUrl
    )
    
    # Extract domain and path from the URL
    $uri = [System.Uri]$rssUrl
    
    # Replace www. with nothing, because it is not interesting
    $hostnameWithoutTld = $uri.Host -replace "www\.",""

    # Remove file type ending (if any) from the path
    $path = ([System.IO.Path]::ChangeExtension($uri.AbsolutePath, $null)) -replace '\.',''

    # Replace "/" with "-"
    $pathWithHyphens = $path -replace "/", "-"

    return ($hostnameWithoutTld + $pathWithHyphens)
}

# Function to display a notification with the latest RSS item
function Show-RssNotification {
    param (
        [string]$title,
        [string]$subtext,
        [string]$link,
        [string]$toastAppLogoSourcePath,
        [string]$notificationgroup,
        [string]$domain
    )
    $Text1 = New-BTText -Content $title
    $Text2 = New-BTText -Content $subtext
    $toastAppLogo = New-Object Microsoft.Toolkit.Uwp.Notifications.ToastGenericAppLogo
    $toastAppLogo.Source = $toastAppLogoSourcePath
    $Binding1 = New-BTBinding -Children $Text1, $Text2 -AppLogoOverride $toastAppLogo
    $Visual1 = New-BTVisual -BindingGeneric $Binding1
    $myToastHeader = New-BTHeader -Id $notificationgroup -Title $notificationgroup -Arguments $domain -ActivationType Protocol
    $action = {
        try {
            Write-Host "Event Activated!"
            Write-Host("Event Arguments: " + $Args.Arguments) -ForegroundColor Green
            # Write-Host("Event UserInput" + $Args.UserInput)
        }
        catch {
            Write-Host "An error occurred within Show-RssNotification: $_"
        }
    }
    $Content1 = New-BTContent -Visual $Visual1 -Launch $link -ActivationType Protocol -Header $myToastHeader
    Submit-BTNotification -Content $Content1 -ActivatedAction $action
}

function Manage-JsonVariable {
    [CmdletBinding(DefaultParameterSetName = 'Save')]
    param (
        [Parameter(ParameterSetName = 'Save', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [switch]$Save,

        [Parameter(ParameterSetName = 'Load', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [switch]$Load,

        [Parameter(ParameterSetName = 'Save', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'Load', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Folder,

        [Parameter(ParameterSetName = 'Save', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'Load', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$VariableName
    )

    if ($Save) {
        $Operation = "Save"
    } elseif ($Load) {
        $Operation = "Load"
    } else {
        Write-Error "Invalid operation. Please use '-Save' or '-Load'."
        return
    }
    

    $FilePath = Join-Path -Path $Folder -ChildPath "$VariableName.json"

    if ($Operation -eq "Save") {
        # Check if the variable exists
        if (Test-Path variable:\$VariableName) {
            # Get the variable value and convert it to JSON, then save to the file
            Get-Variable -Name $VariableName -ValueOnly | ConvertTo-Json | Set-Content -Path $FilePath
            if ($debug) { Write-Host "Variable '$VariableName' saved to '$FilePath'." }
        } else {
            if ($debug) { Write-Host "Variable '$VariableName' does not exist. Cannot save." }
        }
    }  elseif ($Operation -eq "Load") {
        # Check if the file exists
        if (Test-Path $FilePath) {
            # Load JSON from file and return the loaded variable
            $loadedVariable = Get-Content -Path $FilePath | ConvertFrom-Json
            if ($debug) { Write-Host("Variable '$VariableName' loaded from '$FilePath'.") }
            return $loadedVariable
        } else {
            if ($debug) { Write-Host "File '$FilePath' not found. Cannot load. Return Empty Array" }
            return @()
        }
    } else {
        if ($debug) { Write-Host "Invalid operation. Please use 'Load' or 'Save'." }
    }
}

############################################################
# Main loop to send notifications with the latest RSS item #
############################################################

$faviconInfos = @()
foreach($url in $ArrayOfrssUrls){
    # Extract domain from the URL
    $domain = ([uri]$url).Host
    
    # Create the new URL with favicon.ico
    # Define the URL of the image, will be later downloaded once in a temp folder 
    $faviconUrl = "https://$domain/favicon.ico"
    $localUrl = Join-Path -Path $tempFolderPath -ChildPath ($domain + "_favicon.ico")
    # Output the new URL (local and remote)
    $newItem = [PSCustomObject]@{
        remotefile = $faviconUrl
        localfile = $localUrl
    }

    # if ($newItem -notin $faviconInfos){
    $faviconInfos += $newItem
    # }
}


# Must be unique
$faviconInfos = ($faviconInfos | Sort-Object -Property remotefile,localfile -Unique)

# Download all favicons from all rss feed domains and store it in the temp folder
Download-Image -faviconInfos $faviconInfos

# Load the previous notifications from the file in the temporary folder. If there is no file there, then an empty array is returned
$notified = Manage-JsonVariable -Load -Folder $tempFolderPath -VariableName "notified"
if (-not $notified) { $notified = @() }

# On the first pass into the recheckEverySeconds loop.
$recheckEverySecondsCounter = $recheckEverySeconds

while ($true) {
    try {
        if ($recheckEverySecondsCounter -ge $recheckEverySeconds) {
            # Needed to detect if some new notifications were generated. Based on this and if $true, then the $notified Variable is being saved each time.
            $newNotifications = $false
            foreach ($myRSSUrl in $ArrayOfrssUrls) {
                if ($debug){Write-Host("Current RSS-Feed: $myRSSUrl")}
                $rssUrl = $myRSSUrl
                $RssItems = Get-NLatestRssItem -n $MaxNumberOfRSSItemsNotified -myRSSUrl $rssUrl
                # Write-Host($RssItems) - -ForegroundColor Green
                foreach ($rssItem in $RssItems) {
                    if (($rssItem.link -notin $notified) -and ($null -ne $rssItem.link)) {
                        # notify
                        $title_length = ($rssItem.title.Length, 30 | Measure-Object -Minimum).Minimum
                        $subtext_length = ($rssItem.title.Length, 140 | Measure-Object -Minimum).Minimum
                        # Get the current domain and find the local cached filename for the favicon.ico
                        $rssFeedHost = ([uri]$rssUrl).Host # for example www.example.com
                        $rssFeedSheme = ([uri]$rssUrl).Scheme # for example https
                        # Get local favicon location from rssfeed
                        $filePathToIcon = ($faviconInfos.localfile | Where-Object {$_ -like ("*$rssfeedhost*")}) 
                        $domain = $rssFeedSheme + "://" + $rssFeedHost
                        # Generate notifcation group based on the rssUrl
                        $myNotificationGroup = Get-NotificationGroup $rssUrl
                        # Finally, show the notification.
                        if ($title_length -gt 1){
                            Show-RssNotification -title $rssItem.title.SubString(0, $title_length) -subtext $rssItem.title.SubString(0, $subtext_length) -link $rssItem.link -toastAppLogoSourcePath $filePathToIcon -notificationgroup $myNotificationGroup -domain $domain
                        }
                        # Remember the link from which a notification has been generated
                        $notified += $rssItem.link
                        $newNotifications = $true
                    } else {
                        # do not notify
                        if ($debug) { Write-Host (($rssItem.link) + " was already notified.") } else { Write-Host(".") -NoNewLine -ForegroundColor (Get-RandomColor)}
                    }
                }
            }

            if ($newNotifications) {
                # save the notification progress of the notified variable in the notified json file
                Manage-JsonVariable -Save -Folder $tempFolderPath -VariableName "notified"
            }
            $recheckEverySecondsCounter = 0 # Reset the counter
        }
        Start-Sleep -Seconds 1
        
        # Display the progress bar
        $percentComplete = ($recheckEverySecondsCounter / $recheckEverySeconds) * 100
        Write-Progress -PercentComplete $percentComplete -Status "in $($recheckEverySeconds - $recheckEverySecondsCounter) seconds" -Activity "Waiting for next run" -CurrentOperation "Seconds left $($recheckEverySeconds - $recheckEverySecondsCounter)"

        $recheckEverySecondsCounter++
    
    }
    catch {
        Write-Host "An error occurred: $_"
        Start-Sleep -Seconds 60  # Wait for a minute before retrying in case of an error
    }
}