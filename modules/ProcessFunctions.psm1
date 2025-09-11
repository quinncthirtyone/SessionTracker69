function DetectGame() {
    Log "Starting game detection"

    # Fetch games in order of most recent to least recent
    $profileId = Get-ActiveProfile
    $getProfileGamesQuery = "SELECT g.exe_name FROM games g JOIN game_stats gs ON g.id = gs.game_id WHERE gs.profile_id = $profileId ORDER BY gs.last_play_date DESC"
    $getOtherGamesQuery = "SELECT exe_name FROM games WHERE id NOT IN (SELECT game_id FROM game_stats WHERE profile_id = $profileId)"
    $getEmulatorExesQuery = "SELECT exe_name FROM emulated_platforms"

    $profileGameExeList = @((RunDBQuery $getProfileGamesQuery).exe_name)
    $otherGameExeList = @((RunDBQuery $getOtherGamesQuery).exe_name)
    $gameExeList = $profileGameExeList + $otherGameExeList
    $rawEmulatorExes = @((RunDBQuery $getEmulatorExesQuery).exe_name)

    # Flatten the returned result rows containing multiple emulator exes into list with one exe per item
    $emulatorExeList = ($rawEmulatorExes -join ',') -split ','

    $exeList = [string[]] (($gameExeList + $emulatorExeList) | Select-Object -Unique)

    # PERFORMANCE OPTIMIZATION: CPU & MEMORY
    # Process games in batches of 35 with most recent 10 games processed every batch. 5 sec wait b/w every batch.
    # Processes 300 games in 60 sec. Most recent 10 games guaranteed to be detected in 5 sec, accounting for 99% of UX in typical usage.
    # Uses ~ 3% cpu in active blips of less than 1s, every 5s.
    # Benchmarked on a 2019 Ryzen 3550H in low power mode (1.7 GHz Clk with boost disabled), Windows 10 21H2.
    # No new objects are created inside infinite loops to prevent objects explosion, keeps Memory usage ~ 50 MB or less.
    if ($exeList.length -le 35) {
        # If exeList is of size 35 or less. process whole list in every batch
        while ($true) {
            foreach ($exe in $exeList) {
                if ([System.Diagnostics.Process]::GetProcessesByName($exe)) {
                    Log "Found $exe running. Exiting detection"
                    return $exe
                }
            }
            Start-Sleep -s 5
        }
    }
    else {
        # If exeList is longer than 35.
        $startIndex = 10; $batchSize = 25
        while ($true) {
            # Process most recent 10 games in every batch.
            for ($i = 0; $i -lt 10; $i++) {
                if ([System.Diagnostics.Process]::GetProcessesByName($exeList[$i])) {
                    Log "Found $($exeList[$i]) running. Exiting detection"
                    return $exeList[$i]
                }
            }
            # Rest of the games in incrementing way. 25 in each batch.
            $endIndex = [Math]::Min($startIndex + $batchSize, $exeList.length)

            for ($i = $startIndex; $i -lt $endIndex; $i++) {
                if ([System.Diagnostics.Process]::GetProcessesByName($exeList[$i])) {
                    Log "Found $($exeList[$i]) running. Exiting detection"
                    return $exeList[$i]
                }
            }

            if ($startIndex + $batchSize -lt $exeList.length) {
                $startIndex = $startIndex + $batchSize
            }
            else {
                $startIndex = 10
            }

            Start-Sleep -s 5
        }
    }
}

function TimeTrackerLoop($DetectedExe, $IdleDetectionEnabled, $GameName) {
    $hwInfoSensorSession = 'HKCU:\SOFTWARE\HWiNFO64\Sensors\Custom\SessionTracker\Other1'
    $playTimeForCurrentSession = 0
    $totalIdleTimeForCurrentSession = 0
    $exeStartTime = ($null = [System.Diagnostics.Process]::GetProcessesByName($DetectedExe)).StartTime | Sort-Object | Select-Object -First 1

    while ($true) {
        try {
            if (-not ([System.Diagnostics.Process]::GetProcessesByName($DetectedExe))) {
                # Process not running, exit loop
                break
            }
        }
        catch {
            # Handle potential exceptions when process is in a weird state
            Log "Error getting process $DetectedExe. Assuming it has exited. $($_.Exception.Message)"
            break
        }

        $playTimeForCurrentSession = [int16] (New-TimeSpan -Start $exeStartTime).TotalMinutes

        if ($IdleDetectionEnabled) {
            $idleTime = [int16] ([PInvoke.Win32.UserInput]::IdleTime).Minutes

            if ($idleTime -ge 10) {
                $idleSessionStartTime = (Get-Date).AddMinutes(-$idleTime)
                $idleSessionStartTimeUnix = (Get-Date $idleSessionStartTime -UFormat %s).Split('.')[0]
                $idleSessionDuration = 0
                # Entered idle Session
                while ($idleTime -ge 5) {
                    # Track idle Time for current Idle Session
                    $idleSessionDuration = $idleTime
                    $idleTime = [int16] ([PInvoke.Win32.UserInput]::IdleTime).Minutes

                    # Keep the hwinfo sensor updated to current play time session length while tracking idle session
                    $playTimeForCurrentSession = [int16] (New-TimeSpan -Start $exeStartTime).TotalMinutes
                    Set-Itemproperty -path $hwInfoSensorSession -Name 'Value' -value $playTimeForCurrentSession

                    Start-Sleep -s 10
                }
                # Exited Idle Session, record it
                Add-IdleSession -GameName $GameName -SessionStartTime $idleSessionStartTimeUnix -SessionDuration $idleSessionDuration
                $totalIdleTimeForCurrentSession += $idleSessionDuration
            }
        }

        Set-Itemproperty -path $hwInfoSensorSession -Name 'Value' -value $playTimeForCurrentSession
        Start-Sleep -s 10
    }

    Log "Play time for current session: $playTimeForCurrentSession min. Idle time for current session: $totalIdleTimeForCurrentSession min."

    $PlayTimeExcludingIdleTime = $playTimeForCurrentSession - $totalIdleTimeForCurrentSession
    Log "Play time for current session excluding Idle time $PlayTimeExcludingIdleTime min"

    return @($PlayTimeExcludingIdleTime, $totalIdleTimeForCurrentSession, $exeStartTime)
}

function MonitorGame($DetectedExe) {
    Log "Starting monitoring for $DetectedExe"

    $databaseFileHashBefore = CalculateFileHash '.\SessionTracker.db'
    Log "Database hash before: $databaseFileHashBefore"

    $emulatedGameDetails = $null
    $gameName = $null
    $romBasedName = $null
    $entityFound = $null
    $updatedPlayTime = 0
    $updatedLastPlayDate = (Get-Date ([datetime]::UtcNow) -UFormat %s).Split('.').Get(0)

    if (IsExeEmulator $DetectedExe) {
        $emulatedGameDetails = findEmulatedGameDetails $DetectedExe
        if ($emulatedGameDetails -eq $false) {
            Log "Error: Problem in fetching emulated game details. See earlier logs for more info"
            Log "Error: Cannot resume detection until $DetectedExe exits. No playtime will be recorded."

            TimeTrackerLoop $DetectedExe -IdleDetectionEnabled $true -GameName "Unknown"
            return
        }

        $romBasedName = $emulatedGameDetails.RomBasedName
        $entityFound = DoesEntityExists "games" "rom_based_name" $romBasedName
    }
    else {
        $entityFound = DoesEntityExists "games" "exe_name" $DetectedExe
    }

    $idleDetectionEnabled = $true
    if ($null -ne $entityFound) {
        $gameName = $entityFound.name
        if ($entityFound.idle_detection -eq 0) {
            $idleDetectionEnabled = $false
        }
    }
    else {
        $gameName = $romBasedName
    }

    # Create Temp file to signal parent process to update notification icon color to show game is running
    Write-Output "$gameName" > "$env:TEMP\GmGdn-TrackingGame.txt"
    $sessionTimeDetails = TimeTrackerLoop $DetectedExe -IdleDetectionEnabled $idleDetectionEnabled
    $currentPlayTime = $sessionTimeDetails[0]
    $currentIdleTime = $sessionTimeDetails[1]
    $sessionStartTime = $sessionTimeDetails[2]
    # Remove Temp file to signal parent process to update notification icon color to show game has finished
    Remove-Item "$env:TEMP\GmGdn-TrackingGame.txt"

    if ($currentPlayTime -gt 0) {
        RecordSessionHistory -GameName $gameName -SessionStartTime $sessionStartTime -SessionDuration $currentPlayTime
    }

    if ($null -eq $entityFound) {
        Log "Detected emulated game is new and doesn't exist already. Adding to database."

        SaveGame -GameName $gameName -GameExeName $DetectedExe -GameIconPath "./icons/default.png" `
            -GamePlatform $emulatedGameDetails.Platform -GameRomBasedName $gameName -GameIdleDetection $idleDetectionEnabled
    }

    $databaseFileHashAfter = CalculateFileHash '.\SessionTracker.db'
    Log "Database hash after: $databaseFileHashAfter"

    if ($databaseFileHashAfter -ne $databaseFileHashBefore) {
        BackupDatabase
    }
}