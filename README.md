# RSS-Feed-Notifications
Windows notifications about new items in rss feeds with powershell and BurnToast.

The script downloads the RSS feed infos every 300 seconds and creates a Windows notification of the rss feed item, which has not already been notified.

Just add your RSS feed to $ArrayOfrssUrls in order to get notified.
The notified rss feed items will be saved saved in the %temp%\notified.json file on your computer. 
(The link of the rss item will be compared on each loop with the links in the notified.json file)
The news, which are notified, are grouped by the rss feed link

The favicon.ico from each RSS feed will also be saved in the %temp% folder. (Example: `%temp%\my.domain.com_favicon.ico`)

You can add the script to your autorun - for example when the user logs in.

1. Open Startup Folder: `WIN+R` -> `shell:startup`
2. create `fefe.bat` file.
3. Insert content into the batch file (some NuGet Repo Infos should be answered with `Y` ): 
   1. This: `powershell.exe -executionpolicy bypass -windowstyle hidden -noninteractive -nologo -file "c:\path\to\fefe_xml_notif.ps1"`
   2. Or: `powershell.exe -executionpolicy bypass -file "c:\path\to\fefe_xml_notif.ps1" -windowstyle hidden`
4. Enjoy!

