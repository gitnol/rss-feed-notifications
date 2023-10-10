# fefe_blog_notifier
Windows notifications about new blog items in the fefe blog (Felix von Leitner) or other rss feeds with powershell and BurnToast.

The script downloads the RSS feed infos every 300 seconds and creates a Windows notification if the URL has not already been notified.
Just add your RSS feed to $ArrayOfrssUrls
If one link has been notified, this will be saved in the %temp%\notified.json file on your computer.
The favicon.ico from each RSS feed will also be saved in the %temp% folder. (Example: `%temp%\my.domain.com_favicon.ico`)

If you want, start the script when the user logs in.

1. Open Startup Folder: `WIN+R` -> `shell:startup`
2. create `fefe.bat` file.
3. Insert content into the batch file (some NuGet Repo Infos should be answered with `Y` ): 
   1. This: `powershell.exe -executionpolicy bypass -windowstyle hidden -noninteractive -nologo -file "c:\path\to\fefe_xml_notif.ps1"`
   2. Or: `powershell.exe -executionpolicy bypass -file "c:\path\to\fefe_xml_notif.ps1" -windowstyle hidden`
4. Enjoy!

ToDo / Possible Enhancements:
- ~~Monitoring multiple RSS Feeds (at the same time or after one another)~~ -> Done
- ~~Multiple RSS Feeds, multiple FavIcons, which could be downloaded automatically based on the URL~~ -> Done
- ~~Saving and restoring the links, which have already been notified.~~ -> Done