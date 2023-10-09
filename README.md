# fefe_blog_notifier
windows notifications about new blog items in the fefe blog (Felix von Leitner) with powershell and BurnToast

The script downloads the blog RSS file every 300 seconds and creates a Windows notification if the URL has not already been notified.

If you want, start the script when the user logs in.

1. Open Startup Folder: `WIN+R` -> `shell:startup`
2. create `fefe.bat` file.
3. Insert content into the batch file: `powershell.exe -executionpolicy bypass -windowstyle hidden -noninteractive -nologo -file "c:\path\to\fefe_xml_notif.ps1"`
4. Enjoy!

