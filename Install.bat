@echo off
setlocal enabledelayedexpansion

md "%ALLUSERSPROFILE%\SessionTracker"

set "InstallDirectory=%ALLUSERSPROFILE%\SessionTracker"
set "OldInstallDirectory=%ALLUSERSPROFILE%\GamingGaiden"

REM --- MIGRATION LOGIC START ---
IF EXIST "%OldInstallDirectory%" (
    echo Found existing GamingGaiden installation. Migrating data...
    taskkill /f /im GamingGaiden.exe >nul 2>&1
    IF EXIST "%OldInstallDirectory%\GamingGaiden.db" (
        copy "%OldInstallDirectory%\GamingGaiden.db" "%InstallDirectory%\SessionTracker.db"
        echo Database migration successful.
    )
    IF EXIST "%OldInstallDirectory%\backups" (
        xcopy /s/e/q/y "%OldInstallDirectory%\backups" "%InstallDirectory%\backups\"
        echo Backups migration successful.
    )
)
REM --- MIGRATION LOGIC END ---

set "DesktopPath=%USERPROFILE%\Desktop"
set "StartupPath=%APPDATA%\Microsoft\Windows\Start Menu\Programs\StartUp"
set "StartMenuPath=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "IconPath=%InstallDirectory%\icons\running.ico"

REM Quit SessionTracker if Already running (user should close manually)
echo Please ensure SessionTracker is not running before installation.

REM Cleanup Install directory before installation
echo Cleaning install directory
powershell.exe -NoProfile -Command "Get-ChildItem '%InstallDirectory%' -Exclude backups,SessionTracker.db | Remove-Item -recurse -force"

REM Install to C:\ProgramData\SessionTracker
echo Copying Files
xcopy /s/e/q/y "%CD%" "%InstallDirectory%"
del "%InstallDirectory%\Install.bat"

REM Create shortcut using powershell and copy to desktop and start menu
echo.
echo Creating Shortcuts
powershell.exe -NoProfile -Command "$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%InstallDirectory%\SessionTracker.lnk'); $Shortcut.TargetPath = 'powershell.exe'; $Shortcut.Arguments = '-ExecutionPolicy Bypass -WindowStyle Hidden -File ""%InstallDirectory%\SessionTracker.ps1""'; $Shortcut.WorkingDirectory = '%InstallDirectory%'; $Shortcut.IconLocation = '%InstallDirectory%\icons\running.ico'; $Shortcut.Save()"
copy "%InstallDirectory%\SessionTracker.lnk" "%DesktopPath%"
copy "%InstallDirectory%\SessionTracker.lnk" "%StartMenuPath%"

REM Unblock all SessionTracker files as they are downloaded from internet and blocked by default
echo.
echo Unblocking all SessionTracker files
powershell.exe -NoProfile -Command "Get-ChildItem '%InstallDirectory%' -Recurse | Unblock-File"

REM Copy shortcut to startup directory if user chooses to
echo.
set /p AutoStartChoice="Would you like SessionTracker to auto start at boot? Yes/No: "
if /i "%AutoStartChoice%"=="Yes" (
    copy "%InstallDirectory%\SessionTracker.lnk" "%startupPath%"
    echo Auto start successfully setup.
) else if /i "%AutoStartChoice%"=="Y" (
    copy "%InstallDirectory%\SessionTracker.lnk" "%startupPath%"
    echo Auto start successfully setup.
) else (
    echo Auto start setup cancelled by user.
)

echo.
echo Installation successful at %InstallDirectory%. Run application using shortcuts on desktop / start menu.
echo.
echo Your data is in 'SessionTracker.db' file and backups are in 'backups\' folder under %InstallDirectory%.
echo.
echo Backup both to external storage regularly. Otherwise you risk loosing all your data if you reinstall Windows.
echo.
echo You can access %InstallDirectory% by clicking "Settings => Open Install Directory" in app menu.
echo.
echo You can now delete the downloaded files if you wish. Press any key to Exit.
pause >nul
exit /b 0