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

function Update-Session {
    param(
        [int]$SessionId,
        [string]$NewGameName,
        [int]$NewDuration
    )

    Log "Updating session $SessionId with new game name '$NewGameName' and duration '$NewDuration' minutes"

    # Get the profile_id before updating
    $profileId = (RunDBQuery "SELECT profile_id FROM session_history WHERE id = $SessionId").profile_id

    if ($null -eq $profileId) {
        Log "Error: Session with ID $SessionId not found."
        return $null
    }

    $updateQuery = "UPDATE session_history SET game_name = @NewGameName, session_duration_minutes = @NewDuration WHERE id = @SessionId"
    RunDBQuery $updateQuery @{
        NewGameName = $NewGameName
        NewDuration = $NewDuration
        SessionId   = $SessionId
    }

    # The calling function is responsible for triggering the background refresh of HTML files.
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

    return @($oldProfileId, $NewProfileId)
}


function RecordSessionHistory() {
    param(
        [string]$GameName,
        [datetime]$SessionStartTime,
        [int]$SessionDuration
    )

    $profileId = Get-ActiveProfile
    $sessionStartTimeUnix = [int64](($SessionStartTime.ToUniversalTime() - (New-Object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc))).TotalSeconds)

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
    # This function is now a placeholder. The primary data source is session_history,
    # and stats are calculated on the fly. This function could be used in the future
    # for any necessary data migrations or cleanups.
    Log "Update-AllStats is currently a placeholder as stats are calculated on-demand."
}