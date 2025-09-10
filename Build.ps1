[System.Reflection.Assembly]::LoadWithPartialName('System.Web') | out-null

Remove-Item -Recurse .\build\SessionTracker

mkdir -f .\build\SessionTracker

Get-ChildItem -File .\ui\*.html -Exclude 404.html | Remove-Item

pandoc.exe --ascii .\Manual.md -o .\ui\Manual.html

$ManualHTML = Get-Content .\ui\Manual.html
$ManualTemplate = Get-Content .\ui\templates\Manual.html.template

$FinalHTML = $ManualTemplate -replace "_MARKDOWN_HTML_", $ManualHTML

[System.Web.HttpUtility]::HtmlDecode($FinalHTML) | Out-File -encoding UTF8 .\ui\Manual.html

Get-ChildItem .\ui\resources\images\ -Exclude default.png, dropped.png, pc.png, 404.png, 404-tutorial.gif, forever.png, hold.png, finished.png, playing.png, favicon.ico | Remove-Item

# We now include the main .ps1 script directly in the build
$SourceFiles = ".\Install.bat", ".\modules", ".\icons", ".\ui", ".\SessionTracker.ps1"

Copy-Item -Recurse -Path $SourceFiles -Destination .\build\SessionTracker\ -Force

# Add 404 pages for all ui pages for first time render
$fileNames = @("Summary.html", "GamingTime.html", "MostPlayed.html", "AllGames.html", "IdleTime.html", "GamesPerPlatform.html", "PCvsEmulation.html")
foreach ($fileName in $fileNames) {
    Copy-Item -Path .\ui\404.html -Destination .\build\SessionTracker\ui\$fileName -Force
}

# The ps12exe compilation step has been removed.

Compress-Archive -Force -Path .\build\SessionTracker -DestinationPath .\build\SessionTracker.zip

Remove-Item -Recurse .\build\SessionTracker