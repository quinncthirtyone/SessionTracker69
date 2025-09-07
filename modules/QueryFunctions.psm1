function Get-ActiveProfile {
    Log "Getting active profile"
    $getActiveProfileQuery = "SELECT id FROM profiles WHERE is_active = 1"
    $activeProfile = (RunDBQuery $getActiveProfileQuery).id
    Log "Active profile: $activeProfile"
    return $activeProfile
}

function Get-Profiles {
    Log "Getting all profiles"
    $getProfilesQuery = "SELECT * FROM profiles ORDER BY id"
    $profiles = RunDBQuery $getProfilesQuery
    return $profiles
}

function IsExeEmulator($DetectedExe) {
    Log "Is $DetectedExe an Emulator?"

    $pattern = SQLEscapedMatchPattern $DetectedExe.Trim()
    $findExeQuery = "SELECT COUNT(*) as '' FROM emulated_platforms WHERE exe_name LIKE '%{0}%'" -f $pattern

    $exesFound = (RunDBQuery $findExeQuery).Column1

    Log ("Check result: {0}" -f ($exesFound -gt 0))
    return ($exesFound -gt 0)
}

function DoesEntityExists($Table, $Column, $EntityName) {
    Log "Does $EntityName exists in $Table ?"

    $entityNamePattern = SQLEscapedMatchPattern($EntityName.Trim())
    $validateEntityQuery = "SELECT * FROM {0} WHERE {1} LIKE '{2}'" -f $Table, $Column, $entityNamePattern

    $entityFound = RunDBQuery $validateEntityQuery

    Log "Discovered entity: $entityFound"
    return $entityFound
}

function CheckExeCoreCombo($ExeList, $Core) {
    Log "Is $ExeList already registered with $Core?"

    $exeListPattern = SQLEscapedMatchPattern($ExeList.Trim())
    $coreNamePattern = SQLEscapedMatchPattern($Core.Trim())
    $validateEntityQuery = "SELECT * FROM emulated_platforms WHERE exe_name LIKE '%{0}%' AND core LIKE '{1}'" -f $exeListPattern, $coreNamePattern

    $entityFound = RunDBQuery $validateEntityQuery

    Log "Detected exe core Combo: $entityFound"
    return $entityFound
}

function GetPlayTime($GameName) {
    Log "Get existing gameplay time for $GameName"

    $profileId = Get-ActiveProfile
    $gameNamePattern = SQLEscapedMatchPattern($GameName.Trim())
    $getGamePlayTimeQuery = "SELECT SUM(session_duration_minutes) as play_time FROM session_history WHERE game_name LIKE '{0}' AND profile_id = {1}" -f $gameNamePattern, $profileId

    $recordedGamePlayTime = (RunDBQuery $getGamePlayTimeQuery).play_time

    Log "Detected gameplay time: $recordedGamePlayTime min"
    return $recordedGamePlayTime
}

function GetIdleTime($GameName) {
    Log "Get existing game idle time for $GameName"

    $profileId = Get-ActiveProfile
    $gameNamePattern = SQLEscapedMatchPattern($GameName.Trim())
    $getGameIdleTimeQuery = "SELECT SUM(session_duration_minutes) as idle_time FROM idle_sessions WHERE game_name LIKE '{0}' AND profile_id = {1}" -f $gameNamePattern, $profileId

    $recordedGameIdleTime = (RunDBQuery $getGameIdleTimeQuery).idle_time

    Log "Detected game idle time: $recordedGameIdleTime min"
    return $recordedGameIdleTime
}

function findEmulatedGame($DetectedEmulatorExe, $EmulatorCommandLine) {
    Log "Finding emulated game for $DetectedEmulatorExe"

    $pattern = SQLEscapedMatchPattern $DetectedEmulatorExe.Trim()
    $getRomExtensionsQuery = "SELECT rom_extensions FROM emulated_platforms WHERE exe_name LIKE '%{0}%'" -f $pattern
    $romExtensions = (RunDBQuery $getromExtensionsQuery).rom_extensions.Split(',')

    $romName = $null
    foreach ($romExtension in $romExtensions) {
        $romName = [System.Text.RegularExpressions.Regex]::Match($EmulatorCommandLine, "[^`"\\]*\.$romExtension").Value

        if ($romName -ne "") {
            $romName = $romName -replace ".$romExtension", ""
            break
        }
    }

    $romBasedGameName = [regex]::Replace($romName, '\([^)]*\)|\[[^\]]*\]', "")

    Log ("Detected game: {0}" -f $romBasedGameName.Trim())
    return $romBasedGameName.Trim()
}

function findEmulatedGameCore($DetectedEmulatorExe, $EmulatorCommandLine) {
    Log "Finding core in use by $DetectedEmulatorExe"

    $coreName = $null

    $pattern = SQLEscapedMatchPattern $DetectedEmulatorExe.Trim()
    $getCoresQuery = "SELECT core FROM emulated_platforms WHERE exe_name LIKE '%{0}%'" -f $pattern
    $cores = (RunDBQuery $getCoresQuery).core
    if ( $cores.Length -le 1) {
        $coreName = $cores[0]
    }
    else {
        foreach ($core in $cores) {
            if ($EmulatorCommandLine.Contains($core)) {
                $coreName = $core
            }
        }
    }

    Log "Detected core: $coreName"
    return $coreName
}

function findEmulatedGamePlatform($DetectedEmulatorExe, $Core) {
    $getPlatformQuery = $null

    $exePattern = SQLEscapedMatchPattern $DetectedEmulatorExe.Trim()
    if ($Core.Length -eq 0 ) {
        Log "Finding platform for $DetectedEmulatorExe"
        $getPlatformQuery = "SELECT name FROM emulated_platforms WHERE exe_name LIKE '%{0}%' AND core LIKE ''" -f $exePattern
    }
    else {
        Log "Finding platform for $DetectedEmulatorExe and core $Core"
        $corePattern = SQLEscapedMatchPattern $Core.Trim()
        $getPlatformQuery = "SELECT name FROM emulated_platforms WHERE exe_name LIKE '%{0}%' AND core LIKE '{1}'" -f $exePattern, $corePattern
    }

    $emulatedGamePlatform = (RunDBQuery $getPlatformQuery).name

    Log "Detected platform : $emulatedGamePlatform"
    return $emulatedGamePlatform
}

function findEmulatedGameDetails($DetectedEmulatorExe) {
    Log "Finding emulated game details for $DetectedEmulatorExe"

    $emulatorCommandLine = Get-CimInstance -ClassName Win32_Process -Filter "name = '$DetectedEmulatorExe.exe'" | Select-Object -ExpandProperty CommandLine

    $emulatedGameRomBasedName = findEmulatedGame $DetectedEmulatorExe $emulatorCommandLine
    if ($emulatedGameRomBasedName.Length -eq 0) {
        Log "Error: Detected emulated game name of 0 char length. Returning"
        return $false
    }

    $coreName = $null
    if ($DetectedEmulatorExe.ToLower() -like "*retroarch*") {
        Log "Retroarch detected. Detecting core next"
        $coreName = findEmulatedGameCore $DetectedEmulatorExe $emulatorCommandLine

        if ($null -eq $coreName) {
            Log "Error: No core detected. Most likely platform is not registered. Please register platform."
            return $false
        }
    }

    $emulatedGamePlatform = findEmulatedGamePlatform $DetectedEmulatorExe $coreName

    if ($emulatedGamePlatform -is [system.array]) {
        Log "Error: Multiple platforms detected. Returning."
        return $false
    }

    Log "Found emulated game details. Rom Based Name: $emulatedGameRomBasedName, Exe: $DetectedEmulatorExe, Platform: $emulatedGamePlatform"
    return New-Object PSObject -Property @{ RomBasedName = $emulatedGameRomBasedName; Exe = $DetectedEmulatorExe ; Platform = $emulatedGamePlatform }
}

function GetGameDetails($Game) {
    Log "Finding Details of $Game"

    $profileId = Get-ActiveProfile
    $pattern = SQLEscapedMatchPattern $Game.Trim()
    $getGameDetailsQuery = "SELECT
                                g.*,
                                gs.completed,
                                gs.status,
                                COALESCE(sh.session_count, 0) as session_count,
                                sh.last_play_date,
                                COALESCE(sh.play_time, 0) as play_time,
                                COALESCE(i.idle_time, 0) as idle_time
                            FROM
                                games g
                            LEFT JOIN
                                game_stats gs ON g.id = gs.game_id AND gs.profile_id = $profileId
                            LEFT JOIN
                                (SELECT game_name, SUM(session_duration_minutes) as play_time, COUNT(*) as session_count, MAX(session_start_time) as last_play_date FROM session_history WHERE profile_id = $profileId GROUP BY game_name) sh ON g.name = sh.game_name
                            LEFT JOIN
                                (SELECT game_name, SUM(session_duration_minutes) as idle_time FROM idle_sessions WHERE profile_id = $profileId GROUP BY game_name) i ON g.name = i.game_name
                            WHERE g.name LIKE '{1}'" -f $profileId, $pattern
    $gameDetails = RunDBQuery $getGameDetailsQuery

    Log ("Found details: name: {0}, exe_name: {1}, platform: {2}, play_time: {3}" -f $gameDetails.name, $gameDetails.exe_name, $gameDetails.platform, $gameDetails.play_time)
    return $gameDetails
}

function GetPCDetails($PC) {
    Log "Finding Details of $PC"

    $pattern = SQLEscapedMatchPattern $PC.Trim()
    $getPCDetailsQuery = "SELECT * FROM gaming_pcs WHERE name LIKE '{0}'" -f $pattern

    $PCDetails = RunDBQuery $getPCDetailsQuery

    Log ("Found details: name: {0}, cost: {1}, start_date: {2}, end_date: {3}, current: {4}" -f $PCDetails.name, $PCDetails.cost, $PCDetails.start_date, $PCDetails.end_date, $PCDetails.current)
    return $PCDetails
}

function GetPlatformDetails($Platform) {
    Log "Finding Details of $Platform"

    $pattern = SQLEscapedMatchPattern $Platform.Trim()
    $getPlatformDetailsQuery = "SELECT * FROM emulated_platforms WHERE name LIKE '{0}'" -f $pattern

    $platformDetails = RunDBQuery $getplatformDetailsQuery

    Log ("Found details: name: {0}, exe_name: {1}, core: {2}" -f $platformDetails.name, $platformDetails.exe_name, $platformDetails.core)
    return $platformDetails
}

function Add-IdleSession($GameName, $SessionStartTime, $SessionDuration) {
    Log "Recording idle session for $GameName"
    $profileId = Get-ActiveProfile
    $insertIdleSessionQuery = "INSERT INTO idle_sessions (game_name, session_start_time, session_duration_minutes, profile_id) VALUES ('$GameName', $SessionStartTime, $SessionDuration, $profileId)"
    RunDBQuery $insertIdleSessionQuery | Out-Null
}

function Get-IdleSessions {
    Log "Getting all idle sessions"
    $profileId = Get-ActiveProfile
    $getIdleSessionsQuery = "SELECT * FROM idle_sessions WHERE profile_id = $profileId ORDER BY session_start_time DESC"
    $idleSessions = RunDBQuery $getIdleSessionsQuery
    return $idleSessions
}

function Remove-IdleSession($SessionId) {
    Log "Deleting idle session $SessionId"
    $deleteIdleSessionQuery = "DELETE FROM idle_sessions WHERE id = $SessionId"
    RunDBQuery $deleteIdleSessionQuery | Out-Null
}

function Convert-IdleSessionToActive($SessionId) {
    Log "Converting idle session $SessionId to active"

    # 1. Get idle session details
    $getIdleSessionQuery = "SELECT * FROM idle_sessions WHERE id = $SessionId"
    $idleSession = RunDBQuery $getIdleSessionQuery

    if ($null -eq $idleSession) {
        Log "Error: Idle session with ID $SessionId not found."
        return
    }

    # 2. Create a new active session with the same details
    $sessionStartTime = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc).AddSeconds($idleSession.session_start_time)
    RecordSessionHistory -GameName $idleSession.game_name -SessionStartTime $sessionStartTime -SessionDuration $idleSession.session_duration_minutes

    # 3. Delete the idle session
    Remove-IdleSession -SessionId $SessionId
}

function Get-GameStats($GameName) {
    Log "Getting game stats for $GameName"
    $profileId = Get-ActiveProfile
    $gameNamePattern = SQLEscapedMatchPattern($GameName.Trim())
    $getGameStatsQuery = "SELECT gs.* FROM game_stats gs JOIN games g ON gs.game_id = g.id WHERE g.name LIKE '{0}' AND gs.profile_id = {1}" -f $gameNamePattern, $profileId
    $gameStats = RunDBQuery $getGameStatsQuery
    return $gameStats
}