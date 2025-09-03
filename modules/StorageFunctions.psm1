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
        return
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
}

function Switch-SessionProfile($SessionId, $NewProfileId) {
    Log "Switching session $SessionId to profile $NewProfileId"

    # Get session details
    $session = RunDBQuery "SELECT * FROM session_history WHERE id = $SessionId"
    if ($null -eq $session) {
        Log "Session with ID $SessionId not found."
        return
    }

    $gameName = $session.game_name
    $duration = $session.session_duration_minutes
    $oldProfileId = $session.profile_id
    $sessionDate = ([datetime]'1970-01-01 00:00:00Z').AddSeconds($session.session_start_time).ToString("yyyy-MM-dd")

    if ($oldProfileId -eq $NewProfileId) {
        Log "Session is already on this profile."
        return
    }

    # Get game ID
    $gameId = (RunDBQuery "SELECT id FROM games WHERE name LIKE '$gameName'").id

    # Update game_stats for old profile
    $oldGameStats = RunDBQuery "SELECT * FROM game_stats WHERE game_id = $gameId AND profile_id = $oldProfileId"
    if ($null -ne $oldGameStats) {
        $newPlayTime = $oldGameStats.play_time - $duration
        $newSessionCount = $oldGameStats.session_count - 1
        RunDBQuery "UPDATE game_stats SET play_time = $newPlayTime, session_count = $newSessionCount WHERE id = $($oldGameStats.id)"
    }

    # Update game_stats for new profile
    $newGameStats = RunDBQuery "SELECT * FROM game_stats WHERE game_id = $gameId AND profile_id = $NewProfileId"
    if ($null -ne $newGameStats) {
        $newPlayTime = $newGameStats.play_time + $duration
        $newSessionCount = $newGameStats.session_count + 1
        RunDBQuery "UPDATE game_stats SET play_time = $newPlayTime, session_count = $newSessionCount WHERE id = $($newGameStats.id)"
    }
    else {
        # If the game doesn't have stats for the new profile, create them
        RunDBQuery "INSERT INTO game_stats (game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time) VALUES ($gameId, $NewProfileId, $duration, $($session.session_start_time), 'FALSE', 'Playing', 1, 0)"
    }

    # Update daily_playtime for old profile
    $oldDailyPlaytime = RunDBQuery "SELECT * FROM daily_playtime WHERE play_date = '$sessionDate' AND profile_id = $oldProfileId"
    if ($null -ne $oldDailyPlaytime) {
        $newDailyPlayTime = $oldDailyPlaytime.play_time - $duration
        if ($newDailyPlayTime -le 0) {
            RunDBQuery "DELETE FROM daily_playtime WHERE play_date = '$sessionDate' AND profile_id = $oldProfileId"
        }
        else {
            RunDBQuery "UPDATE daily_playtime SET play_time = $newDailyPlayTime WHERE play_date = '$sessionDate' AND profile_id = $oldProfileId"
        }
    }

    # Update daily_playtime for new profile
    $newDailyPlaytime = RunDBQuery "SELECT * FROM daily_playtime WHERE play_date = '$sessionDate' AND profile_id = $NewProfileId"
    if ($null -ne $newDailyPlaytime) {
        $newDailyPlayTime = $newDailyPlaytime.play_time + $duration
        RunDBQuery "UPDATE daily_playtime SET play_time = $newDailyPlayTime WHERE play_date = '$sessionDate' AND profile_id = $NewProfileId"
    }
    else {
        RunDBQuery "INSERT INTO daily_playtime (play_date, play_time, profile_id) VALUES ('$sessionDate', $duration, $NewProfileId)"
    }

    # Update session
    RunDBQuery "UPDATE session_history SET profile_id = $NewProfileId WHERE id = $SessionId"
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