function Set-ActiveProfile($ProfileId) {
    Log "Setting active profile to $ProfileId"
    $updateProfileQuery = "UPDATE profiles SET is_active = CASE WHEN id = @ProfileId THEN 1 ELSE 0 END"
    RunDBQuery $updateProfileQuery @{ ProfileId = $ProfileId }
}

function Update-ProfileName($ProfileId, $ProfileName) {
    Log "Updating profile $ProfileId name to $ProfileName"
    $updateProfileNameQuery = "UPDATE profiles SET name = @ProfileName WHERE id = @ProfileId"
    RunDBQuery $updateProfileNameQuery @{ ProfileId = $ProfileId; ProfileName = $ProfileName }
}

function SaveGame() {
    param(
        [string]$GameName,
        [string]$GameExeName,
        [string]$GameIconPath,
        [string]$GamePlatform,
        [string]$GameRomBasedName = "",
        [bool]$GameIdleDetection = $true
    )

    $profileId = Get-ActiveProfile
    $gameIconBytes = (Get-Content -Path $GameIconPath -Encoding byte -Raw);
    $gameIconColor = Get-DominantColor $gameIconBytes

    # Add game to shared games table if not exists
    $gameExists = DoesEntityExists "games" "name" $GameName
    if ($null -eq $gameExists) {
        $addGameQuery = "INSERT INTO games (name, exe_name, platform, icon, color_hex, rom_based_name, idle_detection) VALUES (@GameName, @GameExeName, @GamePlatform, @gameIconBytes, @GameIconColor, @GameRomBasedName, @GameIdleDetection)"
        RunDBQuery $addGameQuery @{
            GameName          = $GameName.Trim()
            GameExeName       = $GameExeName.Trim()
            GamePlatform      = $GamePlatform.Trim()
            gameIconBytes     = $gameIconBytes
            GameIconColor     = $gameIconColor
            GameRomBasedName  = $GameRomBasedName.Trim()
            GameIdleDetection = $GameIdleDetection
        }
    }

    # Add game stats for the current profile if not exists
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$GameName'").id
    $gameStatsExist = RunDBQuery "SELECT id FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
    if ($null -eq $gameStatsExist) {
        $addGameStatsQuery = "INSERT INTO game_stats (game_id, profile_id, play_time, last_play_date, completed, session_count, idle_time) VALUES (@GameId, @ProfileId, 0, 0, 'FALSE', 0, 0)"
        RunDBQuery $addGameStatsQuery @{
            GameId    = $gameId
            ProfileId = $profileId
        }
    }
}

function SavePlatform() {
    param(
        [string]$PlatformName,
        [string]$EmulatorExeList,
        [string]$CoreName,
        [string]$RomExtensions
    )

    $addPlatformQuery = "INSERT INTO emulated_platforms (name, exe_name, core, rom_extensions)" +
    "VALUES (@PlatformName, @EmulatorExeList, @CoreName, @RomExtensions)"

    Log "Adding $PlatformName in database"
    RunDBQuery $addPlatformQuery @{
        PlatformName    = $PlatformName.Trim()
        EmulatorExeList = $EmulatorExeList.Trim()
        CoreName        = $CoreName.Trim()
        RomExtensions   = $RomExtensions.Trim()
    }
}

function SavePC() {
    param(
        [string]$PCName,
        [string]$PCIconPath,
        [string]$PCCost,
        [string]$PCCurrency,
        [string]$PCStartDate,
        [string]$PCEndDate,
        [string]$PCCurrentStatus
    )

    $PCIconBytes = (Get-Content -Path $PCIconPath -Encoding byte -Raw);

    $addPCQuery = "INSERT INTO gaming_pcs (name, icon, cost, currency, start_date, end_date, current)" +
    "VALUES (@PCName, @PCIconBytes, @PCCost, @PCCurrency, @PCStartDate, @PCEndDate, @PCCurrentStatus)"

    Log "Adding PC $PCName in database"
    RunDBQuery $addPCQuery @{
        PCName          = $PCName.Trim()
        PCIconBytes     = $PCIconBytes
        PCCost          = $PCCost.Trim()
        PCCurrency      = $PCCurrency.Trim()
        PCStartDate     = $PCStartDate
        PCEndDate       = $PCEndDate
        PCCurrentStatus = $PCCurrentStatus
    }
}

function UpdateGameOnSession() {
    param(
        [string]$GameName,
        [string]$GamePlayTime,
        [string]$GameIdleTime,
        [string]$GameLastPlayDate
    )

    $profileId = Get-ActiveProfile
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$GameName'").id

    $getSessionCountQuery = "SELECT session_count FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
    $currentSessionCount = (RunDBQuery $getSessionCountQuery).session_count

    $newSessionCount = $currentSessionCount + 1

    $updateGamePlayTimeQuery = "UPDATE game_stats SET play_time = @UpdatedPlayTime, idle_time = @UpdatedIdleTime, last_play_date = @UpdatedLastPlayDate, session_count = @newSessionCount WHERE game_id = $gameId AND profile_id = $profileId"

    Log "Updating $GameName play time to $GamePlayTime min and idle time to $GameIdleTime min in database for profile $profileId"
    Log "Updating session count from $currentSessionCount to $newSessionCount in database for profile $profileId"

    RunDBQuery $updateGamePlayTimeQuery @{
        UpdatedPlayTime     = $GamePlayTime
        UpdatedIdleTime     = $GameIdleTime
        UpdatedLastPlayDate = $GameLastPlayDate
        newSessionCount     = $newSessionCount
    }
}

function Update-SessionDuration {
    param(
        [int]$SessionId,
        [int]$NewDuration
    )

    Log "Updating session $SessionId duration to $NewDuration minutes"

    # Get the profile_id before updating
    $profileId = (RunDBQuery "SELECT profile_id FROM session_history WHERE id = $SessionId").profile_id

    if ($null -eq $profileId) {
        Log "Error: Session with ID $SessionId not found."
        return $null
    }

    $updateQuery = "UPDATE session_history SET session_duration_minutes = @NewDuration WHERE id = @SessionId"
    RunDBQuery $updateQuery @{
        NewDuration = $NewDuration
        SessionId   = $SessionId
    }

    return @($profileId)
}

function UpdateGameOnEdit() {
    param(
        [string]$OriginalGameName,
        [string]$GameName,
        [string]$GameExeName,
        [string]$GameIconPath,
        [string]$GameCompleteStatus,
        [string]$GamePlatform,
        [string]$GameStatus,
        [bool]$GameIdleDetection
    )

    $profileId = Get-ActiveProfile
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$OriginalGameName'").id

    # Update shared game data
    $gameIconBytes = (Get-Content -Path $GameIconPath -Encoding byte -Raw);
    $gameIconColor = Get-DominantColor $gameIconBytes
    $updateGameQuery = "UPDATE games SET name = @GameName, exe_name = @GameExeName, platform = @GamePlatform, icon = @gameIconBytes, color_hex = @GameIconColor, idle_detection = @GameIdleDetection WHERE id = $gameId"
    RunDBQuery $updateGameQuery @{
        GameName          = $GameName.Trim()
        GameExeName       = $GameExeName.Trim()
        GamePlatform      = $GamePlatform.Trim()
        gameIconBytes     = $gameIconBytes
        GameIconColor     = $gameIconColor
        GameIdleDetection = $GameIdleDetection
    }

    # Upsert profile-specific game stats
    $gameStatsExist = RunDBQuery "SELECT id FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
    if ($null -ne $gameStatsExist) {
        $updateGameStatsQuery = "UPDATE game_stats SET completed = @GameCompleteStatus, status = @GameStatus WHERE game_id = $gameId AND profile_id = $profileId"
        RunDBQuery $updateGameStatsQuery @{
            GameCompleteStatus = $GameCompleteStatus
            GameStatus         = $GameStatus
        }
    }
    else {
        $insertGameStatsQuery = "INSERT INTO game_stats (game_id, profile_id, completed, status, play_time, session_count, last_play_date, idle_time) VALUES (@GameId, @ProfileId, @GameCompleteStatus, @GameStatus, 0, 0, 0, 0)"
        RunDBQuery $insertGameStatsQuery @{
            GameId             = $gameId
            ProfileId          = $profileId
            GameCompleteStatus = $GameCompleteStatus
            GameStatus         = $GameStatus
        }
    }
}

function UpdatePC() {
    param(
        [string]$AddNew = $false,
        [string]$OriginalPCName,
        [string]$PCName,
        [string]$PCIconPath,
        [string]$PCCost,
        [string]$PCCurrency,
        [string]$PCStartDate,
        [string]$PCEndDate,
        [string]$PCCurrentStatus
    )
    
    $PCNamePattern = SQLEscapedMatchPattern($OriginalPCName.Trim())

    if ($AddNew -eq $true) {
        SavePC -PCName $PCName -PCIconPath $PCIconPath -PCCost $PCCost -PCCurrency $PCCurrency -PCStartDate $PCStartDate -PCEndDate $PCEndDate -PCCurrentStatus $PCCurrentStatus
        return
    }

    if ($OriginalPCName -eq $PCName) {

        $PCIconBytes = (Get-Content -Path $PCIconPath -Encoding byte -Raw);
        
        $updatePCQuery = "UPDATE gaming_pcs SET icon = @PCIconBytes, cost = @PCCost, currency = @PCCurrency, start_date = @PCStartDate, end_date = @PCEndDate, current = @PCCurrentStatus WHERE name LIKE '{0}'" -f $PCNamePattern

        Log "Updating PC $PCName in database"
        RunDBQuery $updatePCQuery @{
            PCIconBytes     = $PCIconBytes
            PCCost          = $PCCost
            PCCurrency      = $PCCurrency
            PCStartDate     = $PCStartDate
            PCEndDate       = $PCEndDate
            PCCurrentStatus = $PCCurrentStatus
        }
    }
    else {
        Log "User changed PC's name from $OriginalPCName to $PCName. Need to delete the PC and add it again"
        RemovePC $OriginalPCName
        SavePC -PCName $PCName -PCIconPath $PCIconPath -PCCost $PCCost -PCCurrency $PCCurrency -PCStartDate $PCStartDate -PCEndDate $PCEndDate -PCCurrentStatus $PCCurrentStatus
    }
}

function  UpdatePlatformOnEdit() {
    param(
        [string]$OriginalPlatformName,
        [string]$PlatformName,
        [string]$EmulatorExeList,
        [string]$EmulatorCore,
        [string]$PlatformRomExtensions
    )

    $platformNamePattern = SQLEscapedMatchPattern($OriginalPlatformName.Trim())

    if ( $OriginalPlatformName -eq $PlatformName) {

        $updatePlatformQuery = "UPDATE emulated_platforms set exe_name = @EmulatorExeList, core = @EmulatorCore, rom_extensions = @PlatformRomExtensions WHERE name LIKE '{0}'" -f $platformNamePattern

        Log "Editing $PlatformName in database"
        RunDBQuery $updatePlatformQuery @{
            EmulatorExeList       = $EmulatorExeList
            EmulatorCore          = $EmulatorCore
            PlatformRomExtensions = $PlatformRomExtensions.Trim()
        }
    }
    else {
        Log "User changed platform's name from $OriginalPlatformName to $PlatformName. Need to delete the platform and add it again"
        Log "All games mapped to $OriginalPlatformName will be updated to platform $PlatformName"

        RemovePlatform($OriginalPlatformName)

        SavePlatform -PlatformName $PlatformName -EmulatorExeList $EmulatorExeList -CoreName $EmulatorCore -RomExtensions $PlatformRomExtensions

        $updateGamesPlatformQuery = "UPDATE games SET platform = @PlatformName WHERE platform LIKE '{0}'" -f $platformNamePattern

        RunDBQuery $updateGamesPlatformQuery @{ PlatformName = $PlatformName }
    }
}

function RemoveGame($GameName) {
    Log "Removing $GameName from database"
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$GameName'").id
    RunDBQuery "DELETE FROM game_stats WHERE game_id = $gameId"
    RunDBQuery "DELETE FROM games WHERE id = $gameId"
}

function Reset-IdleTime {
    param(
        [int]$ProfileId
    )

    Log "Resetting idle time for profile $ProfileId"
    $resetIdleTimeQuery = "UPDATE game_stats SET idle_time = 0 WHERE profile_id = @ProfileId"
    RunDBQuery $resetIdleTimeQuery @{ ProfileId = $ProfileId }
}

function RemovePC($PCName) {
    $PCNamePattern = SQLEscapedMatchPattern($PCName.Trim())
    $removePCQuery = "DELETE FROM gaming_pcs WHERE name LIKE '{0}'" -f $PCNamePattern

    Log "Removing PC $PCName from database"
    RunDBQuery $removePCQuery
}

function RemovePlatform($PlatformName) {
    $platformNamePattern = SQLEscapedMatchPattern($PlatformName.Trim())
    $removePlatformQuery = "DELETE FROM emulated_platforms WHERE name LIKE '{0}'" -f $platformNamePattern

    Log "Removing $PlatformName from database"
    RunDBQuery $removePlatformQuery
}

function Remove-Session($SessionId) {
    Log "Removing session $SessionId from database"

    # Get session details
    $session = RunDBQuery "SELECT * FROM session_history WHERE id = $SessionId"
    if ($null -eq $session) {
        Log "Session with ID $SessionId not found."
        return $null
    }

    $gameName = $session.game_name
    $duration = $session.session_duration_minutes
    $profileId = $session.profile_id
    $sessionDate = ([datetime]'1970-01-01 00:00:00Z').AddSeconds($session.session_start_time).ToString("yyyy-MM-dd")

    # Get game ID
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$gameName'").id

    # Update game_stats
    $gameStats = RunDBQuery "SELECT * FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
    if ($null -ne $gameStats) {
        $newPlayTime = $gameStats.play_time - $duration
        $newSessionCount = $gameStats.session_count - 1
        RunDBQuery "UPDATE game_stats SET play_time = $newPlayTime, session_count = $newSessionCount WHERE id = $($gameStats.id)"
    }

    # Update daily_playtime
    $dailyPlaytime = RunDBQuery "SELECT * FROM daily_playtime WHERE play_date = '$sessionDate' AND profile_id = $profileId"
    if ($null -ne $dailyPlaytime) {
        $newDailyPlayTime = $dailyPlaytime.play_time - $duration
        if ($newDailyPlayTime -le 0) {
            RunDBQuery "DELETE FROM daily_playtime WHERE play_date = '$sessionDate' AND profile_id = $profileId"
        }
        else {
            RunDBQuery "UPDATE daily_playtime SET play_time = $newDailyPlayTime WHERE play_date = '$sessionDate' AND profile_id = $profileId"
        }
    }

    # Delete session
    RunDBQuery "DELETE FROM session_history WHERE id = $SessionId"
    return $profileId
}

function Switch-SessionProfile($SessionId, $NewProfileId) {
    Log "Switching session $SessionId to profile $NewProfileId"

    # Get session details
    $session = RunDBQuery "SELECT * FROM session_history WHERE id = $SessionId"
    if ($null -eq $session) {
        Log "Session with ID $SessionId not found."
        return $null
    }

    $gameName = $session.game_name
    $oldProfileId = $session.profile_id
    $sessionDate = ([datetime]'1970-01-01 00:00:00Z').AddSeconds($session.session_start_time).ToLocalTime().ToString("yyyy-MM-dd")

    if ($oldProfileId -eq $NewProfileId) {
        Log "Session is already on this profile."
        return $null
    }

    # Get game ID
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$gameName'").id

    # 1. Update session_history
    RunDBQuery "UPDATE session_history SET profile_id = $NewProfileId WHERE id = $SessionId"
    Log "Updated session history for session $SessionId to profile $NewProfileId"

    # 2. Recalculate stats for both profiles
    foreach ($profileId in @($oldProfileId, $NewProfileId)) {
        Log "Recalculating stats for game '$gameName' on profile $profileId"

        # Recalculate play_time and session_count from session_history
        $recalcQuery = "SELECT COALESCE(SUM(session_duration_minutes), 0) AS total_play_time, COUNT(*) AS total_sessions FROM session_history WHERE game_name LIKE @gameName AND profile_id = @profileId"
        $recalcStats = RunDBQuery $recalcQuery @{ gameName = $gameName; profileId = $profileId }
        
        $totalPlayTime = $recalcStats.total_play_time
        $totalSessions = $recalcStats.total_sessions

        # Get the last play date
        $lastPlayDateQuery = "SELECT MAX(session_start_time) as last_play_date FROM session_history WHERE game_name LIKE @gameName AND profile_id = @profileId"
        $lastPlayDate = (RunDBQuery $lastPlayDateQuery @{ gameName = $gameName; profileId = $profileId }).last_play_date
        if ($null -eq $lastPlayDate) {
            $lastPlayDate = 0
        }

        # Update game_stats
        $gameStatsExist = RunDBQuery "SELECT id FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
        if ($null -ne $gameStatsExist) {
            $updateStatsQuery = "UPDATE game_stats SET play_time = @totalPlayTime, session_count = @totalSessions, last_play_date = @lastPlayDate WHERE game_id = @gameId AND profile_id = @profileId"
            RunDBQuery $updateStatsQuery @{
                totalPlayTime = $totalPlayTime
                totalSessions = $totalSessions
                lastPlayDate  = $lastPlayDate
                gameId        = $gameId
                profileId     = $profileId
            }
            Log "Updated game_stats for game '$gameName' on profile $profileId. Playtime: $totalPlayTime, Sessions: $totalSessions, Last Played: $lastPlayDate"
        } else {
            # If no stats exist for the new profile, create them
            $insertStatsQuery = "INSERT INTO game_stats (game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time) VALUES (@gameId, @profileId, @totalPlayTime, @lastPlayDate, 'FALSE', 'Playing', @totalSessions, 0)"
            RunDBQuery $insertStatsQuery @{
                gameId        = $gameId
                profileId     = $profileId
                totalPlayTime = $totalPlayTime
                lastPlayDate  = $lastPlayDate
                totalSessions = $totalSessions
            }
            Log "Inserted game_stats for game '$gameName' on profile $profileId. Playtime: $totalPlayTime, Sessions: $totalSessions, Last Played: $lastPlayDate"
        }

        # 3. Recalculate daily_playtime for the session date
        Log "Recalculating daily playtime for date '$sessionDate' on profile $profileId"
        $dailyPlayTimeQuery = "SELECT COALESCE(SUM(session_duration_minutes), 0) AS daily_total FROM session_history WHERE strftime('%Y-%m-%d', session_start_time, 'unixepoch', 'localtime') = @sessionDate AND profile_id = @profileId"
        $dailyTotalPlayTime = (RunDBQuery $dailyPlayTimeQuery @{ sessionDate = $sessionDate; profileId = $profileId }).daily_total

        $dailyPlaytimeExists = RunDBQuery "SELECT id FROM daily_playtime WHERE play_date = @sessionDate AND profile_id = @profileId" @{ sessionDate = $sessionDate; profileId = $profileId }

        if ($dailyTotalPlayTime -gt 0) {
            if ($null -ne $dailyPlaytimeExists) {
                $updateDailyQuery = "UPDATE daily_playtime SET play_time = @dailyTotalPlayTime WHERE play_date = @sessionDate AND profile_id = @profileId"
                RunDBQuery $updateDailyQuery @{ dailyTotalPlayTime = $dailyTotalPlayTime; sessionDate = $sessionDate; profileId = $profileId }
                Log "Updated daily_playtime for '$sessionDate' on profile $profileId to $dailyTotalPlayTime minutes."
            } else {
                $insertDailyQuery = "INSERT INTO daily_playtime (play_date, play_time, profile_id) VALUES (@sessionDate, @dailyTotalPlayTime, @profileId)"
                RunDBQuery $insertDailyQuery @{ sessionDate = $sessionDate; dailyTotalPlayTime = $dailyTotalPlayTime; profileId = $profileId }
                Log "Inserted daily_playtime for '$sessionDate' on profile $profileId with $dailyTotalPlayTime minutes."
            }
        } else {
            # If there are no more sessions on this date for the profile, remove the daily_playtime entry
            if ($null -ne $dailyPlaytimeExists) {
                $deleteDailyQuery = "DELETE FROM daily_playtime WHERE play_date = @sessionDate AND profile_id = @profileId"
                RunDBQuery $deleteDailyQuery @{ sessionDate = $sessionDate; profileId = $profileId }
                Log "Deleted daily_playtime for '$sessionDate' on profile $profileId as there are no more sessions."
            }
        }
    }
    return @($oldProfileId, $NewProfileId)
}

function RecordPlaytimOnDate($PlayTime) {
    $profileId = Get-ActiveProfile
    $existingPlayTimeQuery = "SELECT play_time FROM daily_playtime WHERE play_date like DATE('now') AND profile_id = {0}" -f $profileId

    $existingPlayTime = (RunDBQuery $existingPlayTimeQuery).play_time

    $recordPlayTimeQuery = ""
    if ($null -eq $existingPlayTime) {
        $recordPlayTimeQuery = "INSERT INTO daily_playtime(play_date, play_time, profile_id) VALUES (DATE('now'), {0}, {1})" -f $PlayTime, $profileId
    }
    else {
        $updatedPlayTime = $PlayTime + $existingPlayTime

        $recordPlayTimeQuery = "UPDATE daily_playtime SET play_time = {0} WHERE play_date like DATE('now') AND profile_id = {1}" -f $updatedPlayTime, $profileId
    }

    Log "Updating playTime for today in database for profile $profileId"
    RunDBQuery $recordPlayTimeQuery
}

function RecordSessionHistory() {
    param(
        [string]$GameName,
        [datetime]$SessionStartTime,
        [int]$SessionDuration
    )

    $profileId = Get-ActiveProfile
    $sessionStartTimeUnix = (Get-Date $SessionStartTime -UFormat %s).Split('.')[0]

    $insertSessionQuery = "INSERT INTO session_history (game_name, session_start_time, session_duration_minutes, profile_id) VALUES (@GameName, @SessionStartTime, @SessionDuration, @ProfileId)"

    Log "Recording session history for $GameName for profile $profileId"
    RunDBQuery $insertSessionQuery @{
        GameName         = $GameName
        SessionStartTime = $sessionStartTimeUnix
        SessionDuration  = $SessionDuration
        ProfileId        = $profileId
    }
}

function Update-AllStats() {
    param(
        [int[]]$ProfileIds
    )
    Log "Starting full recalculation of all statistics."

    $profilesToProcess = $null
    if ($null -ne $ProfileIds) {
        $profileIdList = $ProfileIds -join ','
        $profilesToProcess = RunDBQuery "SELECT * FROM profiles WHERE id IN ($profileIdList)"
        Log "Recalculating stats for specific profiles: $profileIdList"
    }
    else {
        $profilesToProcess = Get-Profiles
        Log "Recalculating stats for all profiles."
    }

    if ($null -eq $profilesToProcess) {
        Log "No profiles found to process. Aborting recalculation."
        return
    }

    # 1. Recalculate daily_playtime from session_history
    Log "Calculating daily playtime from session_history."
    $getDailyPlaytimeQuery = "SELECT strftime('%Y-%m-%d', session_start_time, 'unixepoch', 'localtime') as play_date, SUM(session_duration_minutes) as play_time, profile_id FROM session_history"
    if ($null -ne $ProfileIds) {
        $profileIdList = $ProfileIds -join ','
        $getDailyPlaytimeQuery += " WHERE profile_id IN ($profileIdList)"
    }
    $getDailyPlaytimeQuery += " GROUP BY play_date, profile_id"
    $dailyPlaytimeData = RunDBQuery $getDailyPlaytimeQuery
    
    Log "Clearing daily_playtime table for affected profiles."
    $deleteDailyPlaytimeQuery = "DELETE FROM daily_playtime"
    if ($null -ne $ProfileIds) {
        $profileIdList = $ProfileIds -join ','
        $deleteDailyPlaytimeQuery += " WHERE profile_id IN ($profileIdList)"
    }
    RunDBQuery $deleteDailyPlaytimeQuery

    Log "Repopulating daily_playtime with calculated data."
    if ($null -ne $dailyPlaytimeData) {
        foreach ($dailyEntry in $dailyPlaytimeData) {
            $insertQuery = "INSERT OR REPLACE INTO daily_playtime (play_date, play_time, profile_id) VALUES (@playDate, @playTime, @profileId)"
            RunDBQuery $insertQuery @{
                playDate  = $dailyEntry.play_date
                playTime  = $dailyEntry.play_time
                profileId = $dailyEntry.profile_id
            }
        }
    }
    Log "Finished repopulating daily_playtime."

    # 2. Recalculate all game_stats
    Log "Recalculating all game_stats."
    $games = RunDBQuery "SELECT id, name FROM games"

    foreach ($game in $games) {
        foreach ($profile in $profilesToProcess) {
            $gameId = $game.id
            $gameName = $game.name
            $profileId = $profile.id

            Log "Recalculating stats for game '$gameName' (ID: $gameId) on profile $profileId"

            # Recalculate play_time and session_count from session_history
            $recalcQuery = "SELECT COALESCE(SUM(session_duration_minutes), 0) AS total_play_time, COUNT(*) AS total_sessions FROM session_history WHERE game_name LIKE @gameName AND profile_id = @profileId"
            $recalcStats = RunDBQuery $recalcQuery @{ gameName = $gameName; profileId = $profileId }

            $totalPlayTime = $recalcStats.total_play_time
            $totalSessions = $recalcStats.total_sessions

            # Get the last play date
            $lastPlayDateQuery = "SELECT MAX(session_start_time) as last_play_date FROM session_history WHERE game_name LIKE @gameName AND profile_id = @profileId"
            $lastPlayDate = (RunDBQuery $lastPlayDateQuery @{ gameName = $gameName; profileId = $profileId }).last_play_date
            if ($null -eq $lastPlayDate) {
                $lastPlayDate = 0
            }

            # Update or Insert game_stats
            $gameStatsExist = RunDBQuery "SELECT id FROM game_stats WHERE game_id = $gameId AND profile_id = $profileId"
            if ($null -ne $gameStatsExist) {
                if ($totalSessions -gt 0) {
                    $updateStatsQuery = "UPDATE game_stats SET play_time = @totalPlayTime, session_count = @totalSessions, last_play_date = @lastPlayDate WHERE game_id = @gameId AND profile_id = @profileId"
                    RunDBQuery $updateStatsQuery @{
                        totalPlayTime = $totalPlayTime
                        totalSessions = $totalSessions
                        lastPlayDate  = $lastPlayDate
                        gameId        = $gameId
                        profileId     = $profileId
                    }
                    Log "Updated game_stats for game '$gameName' on profile $profileId."
                } else {
                    # If no sessions, but stats exist, reset them (except for status/completed flags)
                    $updateStatsQuery = "UPDATE game_stats SET play_time = 0, session_count = 0, last_play_date = 0 WHERE game_id = @gameId AND profile_id = @profileId"
                    RunDBQuery $updateStatsQuery @{ gameId = $gameId; profileId = $profileId }
                    Log "Reset game_stats for game '$gameName' on profile $profileId as no sessions were found."
                }
            } elseif ($totalSessions -gt 0) {
                # If stats don't exist and there are sessions, create a new entry
                $insertStatsQuery = "INSERT INTO game_stats (game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time) VALUES (@gameId, @profileId, @totalPlayTime, @lastPlayDate, 'FALSE', 'Playing', @totalSessions, 0)"
                RunDBQuery $insertStatsQuery @{
                    gameId        = $gameId
                    profileId     = $profileId
                    totalPlayTime = $totalPlayTime
                    lastPlayDate  = $lastPlayDate
                    totalSessions = $totalSessions
                }
                Log "Inserted game_stats for game '$gameName' on profile $profileId."
            }
        }
    }
    Log "Finished recalculating all game_stats."
    Log "Full statistics recalculation complete."
}