
#Requires -Version 5.1

#_pragma iconFile '.\build\GamingGaiden\icons\running.ico'
#_pragma title 'Gaming Gaiden: Gameplay Time Tracker'
#_pragma product 'Gaming Gaiden'
#_pragma copyright '© 2023 Kulvinder Singh'
#_pragma version '2025.07.28'

[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | Out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')          | Out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Web')          	 | Out-null
[System.Reflection.assembly]::LoadwithPartialname("Microsoft.VisualBasic")   | Out-Null

try {
    Import-Module ".\modules\PSSQLite" | Out-Null
    Import-Module ".\modules\ThreadJob" | Out-Null
    Import-Module ".\modules\HelperFunctions.psm1" | Out-Null
    Import-Module ".\modules\QueryFunctions.psm1" | Out-Null
    Import-Module ".\modules\SettingsFunctions.psm1" | Out-Null
    Import-Module ".\modules\SetupDatabase.psm1" | Out-Null
    Import-Module ".\modules\StorageFunctions.psm1" | Out-Null
    Import-Module ".\modules\UIFunctions.psm1" | Out-Null

    #------------------------------------------
    # Functions
    function ResetIconAndSensors() {
        Log "Resetting Icon and Sensors"
        Remove-Item "$env:TEMP\GmGdn-TrackingGame.txt" -ErrorAction silentlycontinue
    Set-Itemproperty -path $HWInfoSensorTracking -Name 'Value' -value 0 | Out-Null
    Set-Itemproperty -path $HWInfoSensorSession -Name 'Value' -value 0 | Out-Null
        $AppNotifyIcon.Text = "Gaming Gaiden"
    }

    function global:Set-RunningIcon() {
        $profileId = Get-ActiveProfile
        if ($profileId -eq 1) {
            $script:IconRunning = [System.Drawing.Icon]::new(".\icons\Pro_1.ico")
        }
        else {
            $script:IconRunning = [System.Drawing.Icon]::new(".\icons\Pro_2.ico")
        }

        # If current icon is not tracking or stopped, it must be a running icon.
        if ($script:AppNotifyIcon.Icon.Handle -ne $script:IconTracking.Handle -and $script:AppNotifyIcon.Icon.Handle -ne $script:IconStopped.Handle) {
            $script:AppNotifyIcon.Icon = $script:IconRunning
        }
    }

    function  StartTrackerJob() {
    Start-ThreadJob -InitializationScript $TrackerJobInitializationScript -ScriptBlock $TrackerJobScript -ArgumentList (,$dbLock) -Name "TrackerJob" | Out-Null
        $StopTrackerMenuItem.Enabled = $true
        $StartTrackerMenuItem.Enabled = $false

        # Reset App Icon & Cleanup Tracking file/reset sensors before starting tracker
        ResetIconAndSensors
        $AppNotifyIcon.Icon = $IconRunning
        Log "Started tracker."
    }

    function  StopTrackerJob() {
    Stop-Job "TrackerJob" -ErrorAction silentlycontinue | Out-Null
        $StopTrackerMenuItem.Enabled = $false
        $StartTrackerMenuItem.Enabled = $true

        # Reset App Icon & Cleanup Tracking file/reset sensors if stopped in middle of Tracking
        ResetIconAndSensors
        $AppNotifyIcon.Icon = $IconStopped
        Log "Stopped tracker"
    }

    function  ExecuteSettingsFunction() {
        Param(
            [scriptblock]$SettingsFunctionToCall,
            [string[]]$EntityList = $null
        )

        $databaseFileHashBefore = CalculateFileHash '.\GamingGaiden.db'; Log "Database hash before: $databaseFileHashBefore"

        if ($null -eq $EntityList) {
            $SettingsFunctionToCall.Invoke()
        }
        else {
            $SettingsFunctionToCall.Invoke((, $EntityList))
        }

        $databaseFileHashAfter = CalculateFileHash '.\GamingGaiden.db'; Log "Database hash after: $databaseFileHashAfter"

        if ($databaseFileHashAfter -ne $databaseFileHashBefore) {
            BackupDatabase
            Log "Rebooting tracker job to apply new settings"
            StopTrackerJob
            StartTrackerJob
            Log "Updating UI to reflect changes"
            UpdateAllStatsInBackground
        }
    }

    function UpdateAppIconToShowTracking() {
        if (Test-Path "$env:TEMP\GmGdn-TrackingGame.txt") {
            $gameName = Get-Content "$env:TEMP\GmGdn-TrackingGame.txt"
            $AppNotifyIcon.Text = "Tracking $gameName"
            $AppNotifyIcon.Icon = $IconTracking
            Set-Itemproperty -path $HWInfoSensorTracking -Name 'Value' -value 1 | Out-Null
        }
        else {
            if ($AppNotifyIcon.Text -ne "Gaming Gaiden") {
                ResetIconAndSensors
                $AppNotifyIcon.Icon = $IconRunning
            }
        }
    }

    #------------------------------------------
    # Exit if Gaming Gaiden is being started from non standard location
    $currentDirectory = (Get-Location).path
    if ($currentDirectory -ne "C:\ProgramData\GamingGaiden") {
        ShowMessage "Launched from non standard location. Please install and use the created shortcuts to start app." "Ok" "Error"
        exit 1;
    }

    #------------------------------------------
    # Exit if Gaming Gaiden is already Running
    $results = [System.Diagnostics.Process]::GetProcessesByName("GamingGaiden")
    if ($results.Length -gt 1) {
        ShowMessage "Gaming Gaiden is already running. Check system tray.`r`nNot Starting another Instance." "Ok" "Error"
        Log "Error: Gaming Gaiden already running. Not Starting another Instance."
        exit 1;
    }

    #------------------------------------------
    # Clear log at application boot if log size has grown above 5 MB
    if ((Test-Path .\GamingGaiden.log) -And ((Get-Item .\GamingGaiden.log).Length / 1MB -gt 5)) {
        Remove-Item ".\GamingGaiden.log" -ErrorAction silentlycontinue
        $timestamp = Get-date -f s
        Log "Log grew more than 5 MB. Clearing."
    }

    #------------------------------------------
    # Setup Database
    Log "Executing database setup"
    SetupDatabase
    Log "Database setup complete"

    # Set active profile to 1 on startup

    #------------------------------------------
    # Integrate With HWiNFO
    $HWInfoSensorTracking = 'HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\Gaming Gaiden\Other0'
    $HWInfoSensorSession = 'HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\Gaming Gaiden\Other1'

    if ((Test-Path "HKCU:\SOFTWARE\HWiNFO64") -And -Not (Test-Path "HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\Gaming Gaiden")) {
        Log "Integrating with HWiNFO"
        New-Item -path 'HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\Gaming Gaiden' -Name 'Other0' -Force | Out-Null
        New-Item -path 'HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\Gaming Gaiden' -Name 'Other1' -Force | Out-Null
        Set-Itemproperty -path $HWInfoSensorTracking -Name 'Name' -value 'Tracking' | Out-Null
        Set-Itemproperty -path $HWInfoSensorTracking -Name 'Unit' -value 'Yes/No' | Out-Null
        Set-Itemproperty -path $HWInfoSensorTracking -Name 'Value' -value 0 | Out-Null
        Set-Itemproperty -path $HWInfoSensorSession -Name 'Name' -value 'Session Length' | Out-Null
        Set-Itemproperty -path $HWInfoSensorSession -Name 'Unit' -value 'Min' | Out-Null
        Set-Itemproperty -path $HWInfoSensorSession -Name 'Value' -value 0 | Out-Null
    }
    else {
        Log "HWiNFO not detected. Or Gaming Gaiden is already Integrated. Skipping Auto Integration"
    }

    #------------------------------------------
    # Database Lock
    $dbLock = New-Object System.Object

    #------------------------------------------
    # Tracker Job Scripts
    $TrackerJobInitializationScript = {
        Import-Module ".\modules\PSSQLite";
        Import-Module ".\modules\HelperFunctions.psm1";
        Import-Module ".\modules\UIFunctions.psm1";
        Import-Module ".\modules\ProcessFunctions.psm1";
        Import-Module ".\modules\QueryFunctions.psm1";
        Import-Module ".\modules\StorageFunctions.psm1";
        Import-Module ".\modules\UserInput.psm1";
    }

    $TrackerJobScript = {
        param($dbLock)
        try {
            while ($true) {
                $detectedExe = DetectGame
                try {
                    [System.Threading.Monitor]::Enter($dbLock)
                    MonitorGame $detectedExe
                    UpdateAllStatsInBackground -ProfileIds (Get-ActiveProfile)
                }
                finally {
                    [System.Threading.Monitor]::Exit($dbLock)
                }
            }
        }
        catch {
            $timestamp = (Get-date -f %d-%M-%y`|%H:%m:%s)
            Write-Output "$timestamp : Error: A user or system error has caused an exception. Check log for details." >> ".\GamingGaiden.log"
            Write-Output "$timestamp : Exception: $($_.Exception.Message)" >> ".\GamingGaiden.log"
            Write-Output "$timestamp : Error: Tracker job has failed. Please restart from app menu to continue detection." >> ".\GamingGaiden.log"
            exit 1;
        }
    }

    #------------------------------------------
    # Setup Timer To Monitor Tracking Updates from Tracker Job
    $Timer = New-Object Windows.Forms.Timer
    $Timer.Interval = 1000
    $Timer.Add_Tick({
        UpdateAppIconToShowTracking;
    })

    #------------------------------------------
    # Setup Tray Icon
    $menuItemSeparator1 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator2 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator3 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator4 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator5 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator6 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator7 = New-Object Windows.Forms.ToolStripSeparator
    $menuItemSeparator8 = New-Object Windows.Forms.ToolStripSeparator

    $IconRunning = [System.Drawing.Icon]::new(".\icons\running.ico")
    $IconTracking = [System.Drawing.Icon]::new(".\icons\tracking.ico")
    $IconStopped = [System.Drawing.Icon]::new(".\icons\stopped.ico")

    $AppNotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $AppNotifyIcon.Text = "Gaming Gaiden"
    $AppNotifyIcon.Icon = $IconRunning
    $AppNotifyIcon.Visible = $true

    # Set active profile to 1 on startup and update icon
    Set-ActiveProfile 1
    Set-RunningIcon

    $allGamesMenuItem = CreateMenuItem "All Games"

    $exitMenuItem = CreateMenuItem "Exit"
    $StartTrackerMenuItem = CreateMenuItem "Start Tracker"
    $StopTrackerMenuItem = CreateMenuItem "Stop Tracker"

    $settingsSubMenuItem = CreateMenuItem "Settings"
    $addGameMenuItem = CreateMenuItem "Add Game"
    $addPlatformMenuItem = CreateMenuItem "Add Emulator"
    $editGameMenuItem = CreateMenuItem "Edit Game"
    $editPlatformMenuItem = CreateMenuItem "Edit Emulator"
    $gamingPCMenuItem = CreateMenuItem "Gaming PCs"
    $nameProfilesMenuItem = CreateMenuItem "Name Profiles"
    $recalculateStatsMenuItem = CreateMenuItem "Recalculate All Statistics"
    $openInstallDirectoryMenuItem = CreateMenuItem "Open Install Directory"
    $null = $settingsSubMenuItem.DropDownItems.Add($addGameMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($editGameMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($menuItemSeparator1)
    $null = $settingsSubMenuItem.DropDownItems.Add($addPlatformMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($editPlatformMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($menuItemSeparator7)
    $null = $settingsSubMenuItem.DropDownItems.Add($gamingPCMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($nameProfilesMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($menuItemSeparator8)
    $null = $settingsSubMenuItem.DropDownItems.Add($recalculateStatsMenuItem)
    $null = $settingsSubMenuItem.DropDownItems.Add($openInstallDirectoryMenuItem)

    $statsSubMenuItem = CreateMenuItem "Statistics"
    $sessionHistoryMenuItem = CreateMenuItem "Session History"
    $gamingTimeMenuItem = CreateMenuItem "Time Spent Gaming"
    $mostPlayedMenuItem = CreateMenuItem "Most Played"
    $idleTimeMenuItem = CreateMenuItem "Idle Time"
    $summaryItem = CreateMenuItem "Life Time Summary"
    $null = $statsSubMenuItem.DropDownItems.Add($summaryItem)
    $null = $statsSubMenuItem.DropDownItems.Add($gamingTimeMenuItem)
    $null = $statsSubMenuItem.DropDownItems.Add($mostPlayedMenuItem)
    $null = $statsSubMenuItem.DropDownItems.Add($idleTimeMenuItem)
    $null = $statsSubMenuItem.DropDownItems.Add($sessionHistoryMenuItem)

    $appContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $switchProfileSubMenuItem = CreateMenuItem "Switch Profile"
    $appContextMenu.Items.AddRange(@($allGamesMenuItem, $menuItemSeparator2, $statsSubMenuItem, $menuItemSeparator3, $settingsSubMenuItem, $menuItemSeparator4, $switchProfileSubMenuItem, $menuItemSeparator5, $StartTrackerMenuItem, $StopTrackerMenuItem, $menuItemSeparator6, $exitMenuItem))
    $AppNotifyIcon.ContextMenuStrip = $appContextMenu

    $profileClickHandler = {
        param($sender, $e)
        $profileId = $sender.Tag
        Set-ActiveProfile $profileId
        Set-RunningIcon
        $AppNotifyIcon.ShowBalloonTip(3000, "Profile Switched", "Switched to $($sender.Text).", [System.Windows.Forms.ToolTipIcon]::Info)
    }

    $appContextMenu.Add_Opening({
            $switchProfileSubMenuItem.DropDownItems.Clear()
            $profiles = Get-Profiles
            $activeProfileId = Get-ActiveProfile

            foreach ($profile in $profiles) {
                $profileMenuItem = CreateMenuItem $profile.name
                $profileMenuItem.Tag = $profile.id

                if ($profile.id -eq $activeProfileId) {
                    $profileMenuItem.Checked = $true
                    $profileMenuItem.Enabled = $false
                }
                $profileMenuItem.Add_Click($profileClickHandler)
                $switchProfileSubMenuItem.DropDownItems.Add($profileMenuItem) | Out-Null
            }
        })

    #------------------------------------------
    # Setup Tray Icon Actions
    $AppNotifyIcon.Add_Click({
            if ($_.Button -eq [Windows.Forms.MouseButtons]::Left) {
                RenderQuickView -IconUpdateCallback { Set-RunningIcon }
            }

            if ($_.Button -eq [Windows.Forms.MouseButtons]::Right) {
                $AppNotifyIcon.ShowContextMenu
            }
        })

    #------------------------------------------
    # Setup Tray Icon Context Menu Actions
    $allGamesMenuItem.Add_Click({
            $profileId = Get-ActiveProfile
            $gamesCheckResult = RenderGameList
            if ($gamesCheckResult -ne $false) {
                Invoke-Item ".\ui\AllGames_$profileId.html"
            }
        })

    $StartTrackerMenuItem.Add_Click({
            StartTrackerJob;
            $AppNotifyIcon.ShowBalloonTip(3000, "Tracker Started", "Watching for game launches.", [System.Windows.Forms.ToolTipIcon]::Info)
        })

    $StopTrackerMenuItem.Add_Click({
            StopTrackerJob
            $AppNotifyIcon.ShowBalloonTip(3000, "Tracker Stopped", "Game launch detection disabled.", [System.Windows.Forms.ToolTipIcon]::Info)
        })

    $exitMenuItem.Add_Click({
            $AppNotifyIcon.Visible = $false;
            Stop-Job -Name "TrackerJob" | Out-Null
            $httpListener.Stop()
            Stop-Job -Name "HttpListenerJob" | Out-Null
            $Timer.Stop()
            $Timer.Dispose()
            [System.Windows.Forms.Application]::Exit();
        })

    #------------------------------------------
    # Statistics Sub Menu Actions
    $summaryItem.Add_Click({
            $profileId = Get-ActiveProfile
            $sessionVsPlaytimeCheckResult = RenderSummary
            if ($sessionVsPlaytimeCheckResult -ne $false) {
                Invoke-Item ".\ui\Summary_$profileId.html"
            }
        })

    $gamingTimeMenuItem.Add_Click({
            $profileId = Get-ActiveProfile
            $gameTimeCheckResult = RenderGamingTime
            if ($gameTimeCheckResult -ne $false) {
                Invoke-Item ".\ui\GamingTime_$profileId.html"
            }
        })

    $mostPlayedMenuItem.Add_Click({
            $profileId = Get-ActiveProfile
            $mostPlayedCheckResult = RenderMostPlayed
            if ($mostPlayedCheckResult -ne $false) {
                Invoke-Item ".\ui\MostPlayed_$profileId.html"
            }
        })

    $idleTimeMenuItem.Add_Click({
            $profileId = Get-ActiveProfile
            $idleTimeCheckResult = RenderIdleTime
            if ($idleTimeCheckResult -ne $false) {
                Invoke-Item ".\ui\IdleTime_$profileId.html"
            }
        })

    $sessionHistoryMenuItem.Add_Click({
            $profileId = Get-ActiveProfile
            $sessionHistoryCheckResult = RenderSessionHistory
            if ($sessionHistoryCheckResult -ne $false) {
                Invoke-Item ".\ui\SessionHistory_$profileId.html"
            }
        })

    #------------------------------------------
    # Settings Sub Menu Actions
    $addGameMenuItem.Add_Click({
            Log "Starting game registration"

            ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderAddGameForm

            # Cleanup temp Files
            Remove-Item -Force "$env:TEMP\GmGdn-*"
        })

    $addPlatformMenuItem.Add_Click({
            Log "Starting emulated platform registration"

            ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderAddPlatformForm
        })

    $editGameMenuItem.Add_Click({
            Log "Starting game editing"

            $gamesList = (RunDBQuery "SELECT name FROM games").name
            if ($gamesList.Length -eq 0) {
                ShowMessage "No Games found in database. Please add few games first." "OK" "Error"
                Log "Error: Games list empty. Returning"
                return
            }

            ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderEditGameForm -EntityList $gamesList

            # Cleanup temp Files
            Remove-Item -Force "$env:TEMP\GmGdn-*"
        })

    $editPlatformMenuItem.Add_Click({
            Log "Starting platform editing"

            $platformsList = (RunDBQuery "SELECT name FROM emulated_platforms").name
            if ($platformsList.Length -eq 0) {
                ShowMessage "No Platforms found in database. Please add few emulators first." "OK" "Error"
                Log "Error: Platform list empty. Returning"
                return
            }

            ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderEditPlatformForm -EntityList $platformsList
        })

    $gamingPCMenuItem.Add_Click({
            Log "Starting Gaming PC registration"

            $PCList = (RunDBQuery "SELECT name FROM gaming_pcs").name

            ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderGamingPCForm -EntityList $PCList

            # Cleanup temp Files
            Remove-Item -Force "$env:TEMP\GmGdn-*"
        })

    $nameProfilesMenuItem.Add_Click({
        Log "Starting profile naming"
        ExecuteSettingsFunction -SettingsFunctionToCall $function:RenderProfileSettingsForm
    })

    $recalculateStatsMenuItem.Add_Click({
        Log "Starting manual recalculation of all statistics."
        try {
            [System.Threading.Monitor]::Enter($dbLock)
            $currentProfileId = Get-ActiveProfile
            Update-AllStats -ProfileIds $currentProfileId
            UpdateAllStatsInBackground -ProfileIds $currentProfileId
        }
        finally {
            [System.Threading.Monitor]::Exit($dbLock)
        }
        $AppNotifyIcon.ShowBalloonTip(3000, "Recalculation Complete", "Statistics for the current profile have been successfully recalculated.", [System.Windows.Forms.ToolTipIcon]::Info)
    })

    $openInstallDirectoryMenuItem.Add_Click({
            Log "Opening Install Directory"
            Invoke-Item .
        })

    #------------------------------------------
    # Launch Application
    Log "Starting tracker on app boot"
    StartTrackerJob

    Log "Starting timer to check for Tracking updates"
    $Timer.Start()

    Log "Hiding powershell window"
    $windowCode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncWindow = Add-Type -MemberDefinition $windowCode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $null = $asyncWindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)

    Log "Informing user of successful application launch."
    $AppNotifyIcon.ShowBalloonTip(3000, "App Launched", "Use tray icon menu for all operations.", [System.Windows.Forms.ToolTipIcon]::Info)

    Log "Starting app context"
    $appContext = New-Object System.Windows.Forms.ApplicationContext

    #------------------------------------------
    # Setup HTTP Listener
    $httpListener = New-Object System.Net.HttpListener
    $httpListener.Prefixes.Add("http://localhost:8088/")
    $httpListener.Start()

    $httpThread = {
        param($httpListener, $dbLock)
        while ($httpListener.IsListening) {
            try {
                $context = $httpListener.GetContext()
                $request = $context.Request
                $response = $context.Response

                # Add CORS headers for all responses
                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                $response.Headers.Add("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
                $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

                # Handle preflight OPTIONS request
                if ($request.HttpMethod -eq "OPTIONS") {
                    $response.StatusCode = 204 # No Content
                    $response.Close()
                    continue # Use continue to proceed to the next iteration of the while loop
                }

                try {
                    [System.Threading.Monitor]::Enter($dbLock)
                    $url = $request.Url.LocalPath
                    Log "HTTP Listener: Received request for $url"
                    $parts = $url.Split("/")
                    $command = $parts[1]

                    if ($command -eq "remove-session") {
                        $sessionId = $parts[2]
                        $profileIdsToUpdate = Remove-Session -SessionId $sessionId
                        UpdateAllStatsInBackground -ProfileIds $profileIdsToUpdate
                    }
                    elseif ($command -eq "switch-session-profile") {
                        $sessionId = $parts[2]
                        $newProfileId = $parts[3]
                        $profileIdsToUpdate = Switch-SessionProfile -SessionId $sessionId -NewProfileId $newProfileId
                        UpdateAllStatsInBackground -ProfileIds $profileIdsToUpdate
                    }
                    elseif ($command -eq "convert-idle-session") {
                        $sessionId = $parts[2]
                        Convert-IdleSessionToActive -SessionId $sessionId
                        UpdateAllStatsInBackground
                    }
                    elseif ($command -eq "delete-idle-session") {
                        $sessionId = $parts[2]
                        Remove-IdleSession -SessionId $sessionId
                        UpdateAllStatsInBackground
                    }
                    elseif ($command -eq "update-session-duration") {
                        $requestBody = (New-Object System.IO.StreamReader($request.InputStream)).ReadToEnd()
                        $requestData = ConvertFrom-Json $requestBody
                        $sessionId = $requestData.sessionId
                        $newDuration = $requestData.newDuration
                        $profileIdsToUpdate = Update-SessionDuration -SessionId $sessionId -NewDuration $newDuration

                        if ($null -ne $profileIdsToUpdate) {
                            Update-AllStats -ProfileIds $profileIdsToUpdate
                        }
                    }
                }
                finally {
                    [System.Threading.Monitor]::Exit($dbLock)
                }

                $response.StatusCode = 200
                $response.Close()
            }
            catch {
                Log "HTTP Listener: An error occurred: $($_.Exception.Message)"
                if ($response -ne $null) {
                    $response.StatusCode = 500
                    $response.Close()
                }
            }
        }
    }
    Start-ThreadJob -InitializationScript $TrackerJobInitializationScript -ScriptBlock $httpThread -ArgumentList ($httpListener, $dbLock) -Name "HttpListenerJob" | Out-Null

    [void][System.Windows.Forms.Application]::Run($appContext)
}
catch {
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | out-null
    [System.Windows.Forms.MessageBox]::Show("Exception: $($_.Exception.Message). Check log for details", 'Gaming Gaiden', "OK", "Error")

    $timestamp = Get-date -f s
    Write-Output "$timestamp : Error: A user or system error has caused an exception. Check log for details." >> ".\GamingGaiden.log"
    Write-Output "$timestamp : Exception: $($_.Exception.Message)" >> ".\GamingGaiden.log"
    exit 1;
}
