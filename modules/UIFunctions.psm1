class Game {
    [ValidateNotNullOrEmpty()][string]$Icon
    [ValidateNotNullOrEmpty()][string]$Name
    [ValidateNotNullOrEmpty()][string]$Platform
    [ValidateNotNullOrEmpty()][string]$Playtime
    [ValidateNotNullOrEmpty()][string]$Session_Count
    [ValidateNotNullOrEmpty()][string]$Completed
    [ValidateNotNullOrEmpty()][string]$Last_Played_On

    Game($IconUri, $Name, $Platform, $Playtime, $SessionCount, $Completed, $LastPlayDate) {
        $this.Icon = $IconUri
        $this.Name = $Name
        $this.Platform = $Platform
        $this.Playtime = $Playtime
        $this.Session_Count = $SessionCount
        $this.Completed = $Completed
        $this.Last_Played_On = $LastPlayDate
    }
}

class GamingPC {
    [ValidateNotNullOrEmpty()][string]$IconUri
    [ValidateNotNullOrEmpty()][string]$Name
    [ValidateNotNullOrEmpty()][string]$Current
    [ValidateNotNullOrEmpty()][string]$Cost
    [ValidateNotNullOrEmpty()][string]$Currency
    [ValidateNotNullOrEmpty()][string]$StartDate
    [ValidateNotNullOrEmpty()][string]$EndDate
    [ValidateNotNullOrEmpty()][string]$Age
    [ValidateNotNullOrEmpty()][string]$TotalHours
    

    GamingPC($IconUri, $Name, $Current, $Cost, $Currency, $StartDate, $EndDate, $Age, $TotalHours) {
        $this.IconUri = $IconUri
        $this.Name = $Name
        $this.Current = $Current
        $this.Cost = $Cost
        $this.Currency = $Currency
        $this.StartDate = $StartDate
        $this.EndDate = $EndDate
        $this.Age = $Age
        $this.TotalHours = $TotalHours
    }
}

class Session {
    [ValidateNotNullOrEmpty()][string]$Icon
    [ValidateNotNullOrEmpty()][string]$Name
    [ValidateNotNullOrEmpty()][string]$Duration
    [ValidateNotNullOrEmpty()][string]$StartTime

    Session($IconUri, $Name, $Duration, $StartTime) {
        $this.Icon = $IconUri
        $this.Name = $Name
        $this.Duration = $Duration
        $this.StartTime = $StartTime
    }
}

function Get-ProfileSwitcherButton($profileId, $pageName) {
    $profiles = Get-Profiles
    $activeProfile = $profiles | Where-Object { $_.id -eq $profileId } | Select-Object -First 1
    $inactiveProfile = $profiles | Where-Object { $_.id -ne $profileId } | Select-Object -First 1

    $buttonClass = if ($inactiveProfile.id -eq 1) { "profile-button-1" } else { "profile-button-2" }
    $onClickPath = "$pageName" + "_$($inactiveProfile.id).html"
    $switcherButton = "<button class='custom-button $buttonClass' onclick=""window.location.href='$onClickPath'"">$($inactiveProfile.name)</button>"
    return $switcherButton
}

function UpdateAllStatsInBackground() {
    param(
        [int[]]$ProfileIds
    )

    $originalActiveProfile = Get-ActiveProfile

    $profilesToProcess = $null
    if ($null -ne $ProfileIds) {
        $profileIdList = $ProfileIds -join ','
        $profilesToProcess = RunDBQuery "SELECT * FROM profiles WHERE id IN ($profileIdList)"
        Log "Rendering reports for specific profiles: $profileIdList"
    }
    else {
        $profilesToProcess = Get-Profiles
        Log "Rendering reports for all profiles."
    }

    if ($null -eq $profilesToProcess) {
        Log "No profiles found to render reports for."
        Set-ActiveProfile $originalActiveProfile # Restore original profile
        return
    }

    foreach ($profile in $profilesToProcess) {
        Set-ActiveProfile $profile.id
        RenderGameList -InBackground $true
        RenderSummary -InBackground $true
        RenderGamingTime -InBackground $true
        RenderMostPlayed -InBackground $true
        RenderIdleTime -InBackground $true
        RenderSessionHistory -InBackground $true
    }

    Set-ActiveProfile $originalActiveProfile
}

function RenderGameList() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering all games list."

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    $getAllGamesQuery = "SELECT
                            g.name,
                            g.icon,
                            g.platform,
                            COALESCE(sh_agg.total_play_time, 0) AS play_time,
                            COALESCE(sh_agg.session_count, 0) AS session_count,
                            gs.completed,
                            gs.last_play_date,
                            gs.status
                        FROM
                            games g
                        LEFT JOIN
                            (SELECT
                                game_name,
                                SUM(session_duration_minutes) AS total_play_time,
                                COUNT(*) AS session_count
                            FROM
                                session_history
                            WHERE
                                profile_id = $profileId
                            GROUP BY
                                game_name) sh_agg ON g.name = sh_agg.game_name
                        LEFT JOIN
                            game_stats gs ON g.id = gs.game_id AND gs.profile_id = $profileId"
    $gameRecords = RunDBQuery $getAllGamesQuery
    if ($gameRecords.Length -eq 0) {
        if(-Not $InBackground) {
            ShowMessage "No Games found in DB for this profile. Please add some games first." "OK" "Error"
        }
        Log "Error: Games list empty for profile $profileId. Returning"
        return $false
    }

    $getMaxPlayTime = "SELECT max(play_time) as 'max_play_time' FROM game_stats WHERE profile_id = $profileId"
    $maxPlayTime = (RunDBQuery $getMaxPlayTime).max_play_time

    $games = [System.Collections.Generic.List[object]]::new()
    $totalPlayTimeQuery = "SELECT SUM(session_duration_minutes) as total_play_time FROM session_history WHERE profile_id = $profileId"
    $totalPlayTime = RunDBQuery $totalPlayTimeQuery

    foreach ($gameRecord in $gameRecords) {
        $name = $gameRecord.name
        $imageFileName = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($name))

        $pngPath = "$workingDirectory\ui\resources\images\$imageFileName.png"
        $jpgPath = "$workingDirectory\ui\resources\images\$imageFileName.jpg"
        $iconPath = ".\resources\images\$imageFileName.png"

        if ($null -eq $gameRecord.icon) {
            $iconPath = ".\resources\images\default.png"
        }
        elseif (-Not (Test-Path $pngPath)) {
            if (Test-Path $jpgPath) {
                $image = [System.Drawing.Image]::FromFile($jpgPath)
                $image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $image.Dispose()
                Remove-Item $jpgPath
            }
            else {
                $iconByteStream = [System.IO.MemoryStream]::new($gameRecord.icon)
                $image = [System.Drawing.Image]::FromStream($iconByteStream)
                $image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $image.Dispose()
            }
        }

        if ($gameRecord.completed -eq 'TRUE') {
            $statusText = "Finished"
            $statusIcon = ".\resources\images\finished.png"
        }
        else {
            $statusText = "Playing"
            $statusIcon = ".\resources\images\playing.png"
        }

        if ($gameRecord.status -eq 'dropped') {
            $statusText = "Dropped"
            $statusIcon = ".\resources\images\dropped.png"
        }
        if ($gameRecord.status -eq 'hold') {
            $statusText = "On Hold"
            $statusIcon = ".\resources\images\hold.png"
        }
        if ($gameRecord.status -eq 'forever') {
            $statusText = "Forever"
            $statusIcon = ".\resources\images\forever.png"
        }

        $gameObject = [pscustomobject]@{
            IconPath      = $iconPath
            Name          = $name
            Platform      = $gameRecord.platform
            Playtime      = $gameRecord.play_time
            SessionCount  = [string]$gameRecord.session_count
            StatusText    = $statusText
            StatusIcon    = $statusIcon
            LastPlayedOn  = $gameRecord.last_play_date
        }
        $null = $games.Add($gameObject)
    }

    $totalPlayTimeString = PlayTimeMinsToString $totalPlayTime.total_play_time

    $gamesData = @{
        games = $games
        maxPlaytime = $maxPlayTime
        totalGameCount = $games.Count
        totalPlaytime = $totalPlayTimeString
    }

    $jsonData = $gamesData | ConvertTo-Json -Depth 5

    $report = (Get-Content $workingDirectory\ui\templates\AllGames.html.template) -replace "_GAMESDATA_", $jsonData
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "AllGames"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\AllGames_$profileId.html"
}

function RenderGamingTime() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering time spent gaming"

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    $getGamingTimeByGameQuery = "SELECT strftime('%Y-%m-%d', session_start_time, 'unixepoch', 'localtime') as play_date, game_name, SUM(session_duration_minutes) as total_duration, g.color_hex FROM session_history sh JOIN games g ON sh.game_name = g.name WHERE sh.profile_id = $profileId GROUP BY play_date, game_name ORDER BY play_date"

    $gamingTimeData = RunDBQuery $getGamingTimeByGameQuery
    if ($gamingTimeData.Length -eq 0) {
        if(-Not $InBackground) {
            ShowMessage "No session history found in DB for this profile. Please play some games first." "OK" "Error"
        }
        Log "Error: Session history empty for profile $profileId. Returning"
        return $false
    }

    $jsonData = $gamingTimeData | ConvertTo-Json -Depth 5 -Compress

    $report = (Get-Content $workingDirectory\ui\templates\GamingTime.html.template) -replace "_GAMINGDATA_", $jsonData
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "GamingTime"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\GamingTime_$profileId.html"
}

function RenderMostPlayed() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering most played"

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    $getGamesPlayTimeDataQuery = "SELECT
                                    g.name,
                                    SUM(sh.session_duration_minutes) as time,
                                    COALESCE(g.color_hex, '#cccccc') as color_hex
                                FROM
                                    games g
                                JOIN
                                    session_history sh ON g.name = sh.game_name
                                WHERE
                                    sh.profile_id = $profileId
                                GROUP BY
                                    g.name
                                ORDER BY
                                    time DESC"
    $gamesPlayTimeData = RunDBQuery $getGamesPlayTimeDataQuery
    if ($gamesPlayTimeData.Length -eq 0) {
        if(-Not $InBackground) {
            ShowMessage "No Games found in DB for this profile. Please add some games first." "OK" "Error"
        }
        Log "Error: Games list empty for profile $profileId. Returning"
        return $false
    }

    $jsonData = @($gamesPlayTimeData) | ConvertTo-Json -Depth 5 -Compress

    if ([string]::IsNullOrEmpty($jsonData)) {
        $jsonData = "[]"
    }

    $report = (Get-Content $workingDirectory\ui\templates\MostPlayed_New.html.template) -replace "_GAMINGDATA_", $jsonData
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "MostPlayed"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\MostPlayed_$profileId.html"
}

function RenderSummary() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering life time summary"

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    $getGamesPlayTimeVsSessionDataQuery = "SELECT g.name, gs.play_time, gs.session_count, gs.completed, gs.status FROM games g JOIN game_stats gs ON g.id = gs.game_id WHERE gs.profile_id = $profileId"
    $gamesPlayTimeVsSessionData = RunDBQuery $getGamesPlayTimeVsSessionDataQuery
    if ($gamesPlayTimeVsSessionData.Length -eq 0) {
        if(-Not $InBackground) {
            ShowMessage "No Games found in DB for this profile. Please add some games first." "OK" "Error"
        }
        Log "Error: Games list empty for profile $profileId. Returning"
        return $false
    }

    $getGamingPCsQuery = "SELECT gp.*,
                            COALESCE(SUM(sh.session_duration_minutes) / 60, 0) AS total_hours,
                            CAST((julianday(COALESCE(datetime(gp.end_date, 'unixepoch'), datetime('now'))) - julianday(datetime(gp.start_date, 'unixepoch'))) / 365.25 AS INTEGER) AS age_years,
                            CAST((julianday(COALESCE(datetime(gp.end_date, 'unixepoch'), datetime('now'))) - julianday(datetime(gp.start_date, 'unixepoch'))) % 365.25 / 30.4375 AS INTEGER) AS age_months
                        FROM
                            gaming_pcs gp
                        LEFT JOIN
                            session_history sh
                        ON
                            sh.session_start_time BETWEEN gp.start_date AND COALESCE(gp.end_date, strftime('%s', 'now'))
                        WHERE sh.profile_id = $profileId
                        GROUP BY
                            gp.name
                        ORDER BY
                            gp.current DESC, gp.end_date DESC;"
    $gamingPCData = RunDBQuery $getGamingPCsQuery

    $TotalAnnualGamingHoursQuery = "SELECT
                                        STRFTIME('%Y', session_start_time, 'unixepoch') AS Year,
                                        SUM(session_duration_minutes) / 60 AS TotalPlayTime
                                    FROM
                                        session_history
                                    WHERE profile_id = $profileId
                                    GROUP BY
                                        Year
                                    ORDER BY
                                        Year;"
    $totalAnnualGamingHoursData = RunDBQuery $TotalAnnualGamingHoursQuery

    $gamingPCs = [System.Collections.Generic.List[GamingPC]]::new()
    $pcIconUri = $null

    foreach ($gamingPCRecord in $gamingPCData) {
        $name = $gamingPCRecord.name
        $imageFileName = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($name))
        
        $iconByteStream = [System.IO.MemoryStream]::new($gamingPCRecord.icon)
        $iconBitmap = [System.Drawing.Bitmap]::FromStream($iconByteStream)

        if ($iconBitmap.PixelFormat -eq "Format32bppArgb") {
            $iconBitmap.Save("$workingDirectory\ui\resources\images\$imageFileName.png", [System.Drawing.Imaging.ImageFormat]::Png)
            $pcIconUri = ".\resources\images\$imageFileName.png"
        }
        else {
            $iconBitmap.Save("$workingDirectory\ui\resources\images\$imageFileName.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $pcIconUri = ".\resources\images\$imageFileName.jpg"
        }

        $iconBitmap.Dispose()

        $pcAge = "{0} Years and {1} Months" -f $gamingPCRecord.age_years, $gamingPCRecord.age_months

        $thisPC = [GamingPC]::new($pcIconUri, $name, $gamingPCRecord.current, $gamingPCRecord.cost, $gamingPCRecord.currency, $gamingPCRecord.start_date, $gamingPCRecord.end_date, $pcAge, $gamingPCRecord.total_hours)

        $null = $gamingPCs.add($thisPC)
    }

    $getSessionHistorySummaryQuery = "SELECT
                                        COUNT(DISTINCT game_name) AS total_games,
                                        SUM(session_duration_minutes) AS total_play_time,
                                        COUNT(*) AS total_sessions,
                                        MIN(session_start_time) AS min_play_date,
                                        MAX(session_start_time) AS max_play_date
                                    FROM session_history
                                    WHERE profile_id = $profileId"
    $sessionSummaryData = RunDBQuery $getSessionHistorySummaryQuery

    if (($null -eq $sessionSummaryData) -or ($null -eq $sessionSummaryData.min_play_date) -or ($null -eq $sessionSummaryData.max_play_date)) {
        if(-Not $InBackground) {
            ShowMessage "No play time found in DB for this profile. Please play some games first." "OK" "Error"
        }
        Log "Error: No playtime found in DB for profile $profileId. Returning"
        return $false
    }

    $totalIdleTimeQuery = "SELECT SUM(session_duration_minutes) AS total_idle_time FROM idle_sessions WHERE profile_id = $profileId"
    $totalIdleTimeMinutes = (RunDBQuery $totalIdleTimeQuery).total_idle_time

    $minDate = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $startDate = $minDate.AddSeconds($sessionSummaryData.min_play_date).ToLocalTime().ToString("MMM yyyy")
    $endDate = $minDate.AddSeconds($sessionSummaryData.max_play_date).ToLocalTime().ToString("MMM yyyy")

    $totalPlayTime = PlayTimeMinsToString $sessionSummaryData.total_play_time
    $totalIdleTime = PlayTimeMinsToString $totalIdleTimeMinutes

    $summaryStatement = "<b>Duration: </b>$startDate - $endDate. <b>Games: </b>$($sessionSummaryData.total_games). <b>Sessions: </b>$($sessionSummaryData.total_sessions).<br><br><b>Play time: </b>$totalPlayTime. <b>Idle time: </b>$totalIdleTime."

    $summaryTable = $gamesPlayTimeVsSessionData | ConvertTo-Html -Fragment
    if ($summaryTable) {
        $summaryTable = $summaryTable.Replace('<table>', '<table><tbody>').Replace('</table>', '</tbody></table>')
    }
    $pcTable = $gamingPCs | ConvertTo-Html -Fragment
    if ($pcTable) {
        $pcTable = $pcTable.Replace('<table>', '<table><tbody>').Replace('</table>', '</tbody></table>')
    }
    $annualHoursTable = $totalAnnualGamingHoursData | ConvertTo-Html -Fragment
    if ($annualHoursTable) {
        $annualHoursTable = $annualHoursTable.Replace('<table>', '<table><tbody>').Replace('</table>', '</tbody></table>')
    }

    $report = (Get-Content $workingDirectory\ui\templates\Summary.html.template) -replace "_SUMMARYTABLE_", $summaryTable
    $report = $report -replace "_SUMMARYSTATEMENT_", $summaryStatement
    $report = $report -replace "_ANNUALGAMINGHOURSTABLE_", $annualHoursTable
    $report = $report -replace "_PCTABLE_", $pcTable
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "Summary"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\Summary_$profileId.html"
}

function RenderIdleTime() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering Idle time"

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    $getGamesIdleTimeDataQuery = "SELECT
                                    g.name,
                                    ROUND(SUM(i.session_duration_minutes) / 60.0, 2) as time,
                                    COALESCE(g.color_hex, '#cccccc') as color_hex
                                FROM
                                    games g
                                JOIN
                                    idle_sessions i ON g.name = i.game_name
                                WHERE
                                    i.profile_id = $profileId
                                GROUP BY
                                    g.name
                                ORDER BY
                                    time DESC"
    $gamesIdleTimeData = @(RunDBQuery $getGamesIdleTimeDataQuery)
    if ($gamesIdleTimeData.Length -eq 0) {
        if(-Not $InBackground) {
        }
        Log "Info: Idle Games list empty for profile $profileId. Generating empty report."
        $jsonData = "[]"
    }
    else {
        $getTotalIdleTimeQuery = "SELECT SUM(session_duration_minutes) as total_idle_time FROM idle_sessions WHERE profile_id = $profileId"
        $totalIdleTime = (RunDBQuery $getTotalIdleTimeQuery).total_idle_time
        $totalIdleTimeInHours = [math]::Round($totalIdleTime / 60.0, 2)
        $totalIdleTimeObject = [pscustomobject]@{
            name      = "AFK Total"
            time      = $totalIdleTimeInHours
            color_hex = '#ff6384'
        }
        $gamesIdleTimeData += $totalIdleTimeObject

        $jsonData = $gamesIdleTimeData | ConvertTo-Json -Depth 5 -Compress
    }

    $report = (Get-Content $workingDirectory\ui\templates\IdleTime.html.template) -replace "_GAMINGDATA_", $jsonData
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "IdleTime"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\IdleTime_$profileId.html"
}

function RenderSessionHistory() {
    param(
        [bool]$InBackground = $false
    )

    Log "Rendering session history data for client-side processing."

    $profileId = Get-ActiveProfile
    $workingDirectory = (Get-Location).Path

    # Get active sessions
    $getSessionHistoryQuery = "SELECT sh.id, sh.game_name, sh.session_start_time, sh.session_duration_minutes, g.icon, 'Active' as type FROM session_history sh LEFT JOIN games g ON sh.game_name = g.name WHERE sh.profile_id = $profileId"
    $activeSessions = RunDBQuery $getSessionHistoryQuery

    # Get idle sessions
    $getIdleSessionsQuery = "SELECT id, game_name, session_start_time, session_duration_minutes, 'Idle' as type FROM idle_sessions WHERE profile_id = $profileId"
    $idleSessions = RunDBQuery $getIdleSessionsQuery

    # Combine and sort sessions
    $allSessions = $activeSessions + $idleSessions
    $allSessions = $allSessions | Sort-Object -Property session_start_time -Descending

    $sessionData = [System.Collections.Generic.List[object]]::new()

    foreach ($sessionRecord in $allSessions) {
        # --- Robust Icon Path Generation ---
        $gameName = $sessionRecord.game_name
        $imageFileName = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($gameName))
        $pngPath = "$workingDirectory\ui\resources\images\$imageFileName.png"
        $jpgPath = "$workingDirectory\ui\resources\images\$imageFileName.jpg"
        $iconPath = ".\resources\images\$imageFileName.png"

        if (-Not (Test-Path $pngPath)) {
            if (Test-Path $jpgPath) {
                $image = [System.Drawing.Image]::FromFile($jpgPath)
                $image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $image.Dispose()
                Remove-Item $jpgPath
            }
            else {
                $icon = (RunDBQuery "SELECT icon FROM games WHERE name LIKE '$gameName'").icon
                if ($null -ne $icon) {
                    $iconByteStream = [System.IO.MemoryStream]::new($icon)
                    $image = [System.Drawing.Image]::FromStream($iconByteStream)
                    $image.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $image.Dispose()
                }
            }
        }
        # --- End Icon Logic ---

        # --- Data Formatting ---
        $durationMinutes = $sessionRecord.session_duration_minutes
        $hours = [math]::Floor($durationMinutes / 60)
        $minutes = $durationMinutes % 60
        $durationFormatted = "{0}h {1}m" -f $hours, $minutes

        [datetime]$origin = '1970-01-01 00:00:00'
        $sessionDateTime = $origin.AddSeconds($sessionRecord.session_start_time).ToLocalTime()
        $startDateFormatted = $sessionDateTime.ToString("yyyy-MM-dd")
        $startTimeFormatted = $sessionDateTime.ToString("HH:mm:ss")
        $endTimeFormatted = $sessionDateTime.AddMinutes($durationMinutes).ToString("HH:mm:ss")
        # --- End Data Formatting ---

        $sessionObject = [pscustomobject]@{
            Id        = $sessionRecord.id
            GameName  = $gameName
            IconPath  = $iconPath
            Duration  = $durationFormatted
            StartDate = $startDateFormatted
            StartTime = $startTimeFormatted
            EndTime   = $endTimeFormatted
            Type      = $sessionRecord.type
        }
        $null = $sessionData.Add($sessionObject)
    }

    $jsonData = @($sessionData) | ConvertTo-Json -Depth 5
    if ([string]::IsNullOrEmpty($jsonData)) {
        $jsonData = "[]"
    }

    $profiles = Get-Profiles
    $profilesJson = $profiles | ConvertTo-Json -Depth 2
    $report = (Get-Content $workingDirectory\ui\templates\SessionHistory.html.template) -replace '_SESSIONDATA_', $jsonData
    $report = $report -replace '_PROFILEDATA_', $profilesJson
    $report = $report -replace 'Summary.html', "Summary_$profileId.html"
    $report = $report -replace 'GamingTime.html', "GamingTime_$profileId.html"
    $report = $report -replace 'MostPlayed.html', "MostPlayed_$profileId.html"
    $report = $report -replace 'AllGames.html', "AllGames_$profileId.html"
    $report = $report -replace 'IdleTime.html', "IdleTime_$profileId.html"
    $report = $report -replace 'SessionHistory.html', "SessionHistory_$profileId.html"

    $switcherButton = Get-ProfileSwitcherButton $profileId "SessionHistory"
    $report = $report -replace '_PROFILE_SWITCHER_', $switcherButton

    $report | Out-File -encoding UTF8 "$workingDirectory\ui\SessionHistory_$profileId.html"
}

function RenderAboutDialog() {
    $aboutForm = CreateForm "About" 350 280 ".\icons\running.ico"

    $pictureBox = CreatePictureBox "./icons/banner.png" 0 10 345 70
    $aboutForm.Controls.Add($pictureBox)

    $labelVersion = CreateLabel "v2025.07.28" 145 90
    $aboutForm.Controls.Add($labelVersion)

    $textCopyRight = [char]::ConvertFromUtf32(0x000000A9) + " 2023 Kulvinder Singh"
    $labelCopyRight = CreateLabel $textCopyRight 112 110
    $aboutForm.Controls.Add($labelCopyRight)

    $labelHome = New-Object Windows.Forms.LinkLabel
    $labelHome.Text = "Home"
    $labelHome.Location = New-Object Drawing.Point(160, 140)
    $labelHome.AutoSize = $true
    $labelHome.Add_LinkClicked({
            Start-Process "https://github.com/kulvind3r/GamingGaiden"
        })
    $aboutForm.Controls.Add($labelHome)

    $labelAttributions = New-Object Windows.Forms.LinkLabel
    $labelAttributions.Text = "Open Source And Original Art Attributions"
    $labelAttributions.Location = New-Object Drawing.Point(70, 165)
    $labelAttributions.AutoSize = $true
    $labelAttributions.Add_LinkClicked({
            Start-Process "https://github.com/kulvind3r/GamingGaiden#attributions"
        })
    $aboutForm.Controls.Add($labelAttributions)

    $buttonClose = CreateButton "Close" 140 205; $buttonClose.Add_Click({ $pictureBox.Image.Dispose(); $pictureBox.Dispose(); $aboutForm.Dispose() }); $aboutForm.Controls.Add($buttonClose)

    $aboutForm.ShowDialog()
    $pictureBox.Image.Dispose(); $pictureBox.Dispose();
    $aboutForm.Dispose()
}

function RenderQuickView() {
    param(
        [scriptblock]$IconUpdateCallback
    )
    $quickViewForm = CreateForm "Quick View" 420 100 ".\icons\running.ico"
    $quickViewForm.MaximizeBox = $false
    $quickViewForm.MinimizeBox = $false
    $quickViewForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual

    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $quickViewForm.Left = $screenBounds.Width - $quickViewForm.Width - 20

    $dataGridView = New-Object System.Windows.Forms.DataGridView
    $dataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $dataGridView.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $dataGridView.RowTemplate.Height = 65
    $dataGridView.AllowUserToAddRows = $false
    $dataGridView.RowHeadersVisible = $false
    $dataGridView.CellBorderStyle = "None"
    $dataGridView.AutoSizeColumnsMode = "Fill"
    $dataGridView.Enabled = $false
    $dataGridView.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)
    $dataGridView.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

    $doubleBufferProperty = $dataGridView.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
    $doubleBufferProperty.SetValue($dataGridView, $true, $null)

    $bottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $bottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $bottomPanel.ColumnCount = 2
    $bottomPanel.RowCount = 1
    $bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $bottomPanel.Height = 30

    $toggleSwitch = New-Object System.Windows.Forms.CheckBox
    $toggleSwitch.Text = "Show Most Played"
    $toggleSwitch.Dock = [System.Windows.Forms.DockStyle]::Fill
    $toggleSwitch.Appearance = [System.Windows.Forms.Appearance]::Button
    $toggleSwitch.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $toggleSwitch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $toggleSwitch.FlatAppearance.BorderSize = 0
    $toggleSwitch.BackColor = [System.Drawing.Color]::White

    $profileSwitch = New-Object System.Windows.Forms.Button
    $profileSwitch.Dock = [System.Windows.Forms.DockStyle]::Fill
    $profileSwitch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $profileSwitch.FlatAppearance.BorderSize = 0
    $profileSwitch.BackColor = [System.Drawing.Color]::White

    $bottomPanel.Controls.Add($toggleSwitch, 0, 0)
    $bottomPanel.Controls.Add($profileSwitch, 1, 0)

    function Resize-Form() {
        $totalRowsHeight = 0
        foreach ($row in $dataGridView.Rows) {
            $totalRowsHeight += $row.Height
        }
        $headerHeight = if ($dataGridView.ColumnHeadersVisible) { $dataGridView.ColumnHeadersHeight } else { 0 }
        $toggleHeight = $bottomPanel.Height
        $newHeight = $totalRowsHeight + $headerHeight + $toggleHeight
        $quickViewForm.ClientSize = New-Object System.Drawing.Size($quickViewForm.ClientSize.Width, $newHeight)
        $quickViewForm.Top = $screenBounds.Height - $quickViewForm.Height - 60
    }

    function Load-Data() {
        if ($toggleSwitch.Checked) {
            Load-MostPlayed
        } else {
            Load-RecentSessions
        }
        $dataGridView.ClearSelection()
        Update-ProfileSwitchText
    }

    function Update-ProfileSwitchText() {
        $profiles = Get-Profiles
        $activeProfileId = Get-ActiveProfile
        $inactiveProfile = $profiles | Where-Object { $_.id -ne $activeProfileId } | Select-Object -First 1
        $profileSwitch.Text = "Switch to " + $inactiveProfile.name
    }

    function Load-RecentSessions {
        $quickViewForm.text = "Recent Sessions"
        $toggleSwitch.Text = "Show Most Played"
        $dataGridView.Rows.Clear()
        $dataGridView.Columns.Clear()

        $profileId = Get-ActiveProfile
        $lastFiveSessionsQuery = "SELECT sh.game_name, g.icon, sh.session_duration_minutes, sh.session_start_time FROM session_history sh JOIN games g ON sh.game_name = g.name WHERE sh.profile_id = {0} ORDER BY sh.session_start_time DESC LIMIT 5" -f $profileId
        $sessionRecords = RunDBQuery $lastFiveSessionsQuery
        if ($sessionRecords.Length -eq 0) {
            $dataGridView.Columns.Clear()
            $dataGridView.Rows.Clear()
            $dataGridView.Refresh()
            return
        }

        $IconColumn = New-Object System.Windows.Forms.DataGridViewImageColumn
        $IconColumn.Name = "icon"
        $IconColumn.HeaderText = ""
        $IconColumn.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
        $null = $dataGridView.Columns.Add($IconColumn)

        $null = $dataGridView.Columns.Add("name", "Name")
        $null = $dataGridView.Columns.Add("duration", "Duration")
        $null = $dataGridView.Columns.Add("played_on", "Played On")

        foreach ($column in $dataGridView.Columns) {
            $column.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
        }

        foreach ($row in $sessionRecords) {
            $iconByteStream = [System.IO.MemoryStream]::new($row.icon)
            $gameIcon = [System.Drawing.Bitmap]::FromStream($iconByteStream)
            $minutes = $null; $hours = [math]::divrem($row.session_duration_minutes, 60, [ref]$minutes);
            $durationFormatted = "{0} Hr {1} Min" -f $hours, $minutes
            [datetime]$origin = '1970-01-01 00:00:00'
            $dateFormatted = $origin.AddSeconds($row.session_start_time).ToLocalTime().ToString("dd MMM HH:mm")
            $null = $dataGridView.Rows.Add($gameIcon, $row.game_name, $durationFormatted, $dateFormatted)
        }
        Resize-Form
    }

    function Load-MostPlayed {
        $quickViewForm.text = "Most Played Games"
        $toggleSwitch.Text = "Show Recent Sessions"
        $dataGridView.Rows.Clear()
        $dataGridView.Columns.Clear()

        $profileId = Get-ActiveProfile
        $mostPlayedQuery = "SELECT g.name, g.icon, gs.play_time, gs.last_play_date FROM games g JOIN game_stats gs ON g.id = gs.game_id WHERE gs.profile_id = {0} ORDER BY gs.play_time DESC LIMIT 5" -f $profileId
        $gameRecords = RunDBQuery $mostPlayedQuery
        if ($gameRecords.Length -eq 0) {
            $dataGridView.Columns.Clear()
            $dataGridView.Rows.Clear()
            $dataGridView.Refresh()
            return
        }

        $IconColumn = New-Object System.Windows.Forms.DataGridViewImageColumn
        $IconColumn.Name = "icon"
        $IconColumn.HeaderText = ""
        $IconColumn.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
        $null = $dataGridView.Columns.Add($IconColumn)

        $null = $dataGridView.Columns.Add("name", "Name")
        $null = $dataGridView.Columns.Add("play_time", "Playtime")
        $null = $dataGridView.Columns.Add("last_play_date", "Last Played On")

        foreach ($column in $dataGridView.Columns) {
            $column.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
        }

        foreach ($row in $gameRecords) {
            $iconByteStream = [System.IO.MemoryStream]::new($row.icon)
            $gameIcon = [System.Drawing.Bitmap]::FromStream($iconByteStream)
            $minutes = $null; $hours = [math]::divrem($row.play_time, 60, [ref]$minutes);
            $playTimeFormatted = "{0} Hr {1} Min" -f $hours, $minutes
            [datetime]$origin = '1970-01-01 00:00:00'
            $dateFormatted = $origin.AddSeconds($row.last_play_date).ToLocalTime().ToString("dd MMMM yyyy")
            $null = $dataGridView.Rows.Add($gameIcon, $row.name, $playTimeFormatted, $dateFormatted)
        }
        Resize-Form
    }

    $toggleSwitch.Add_CheckedChanged({
        Load-Data
    })

    $profileSwitch.Add_Click({
        $profiles = Get-Profiles
        $activeProfileId = Get-ActiveProfile
        $inactiveProfile = $profiles | Where-Object { $_.id -ne $activeProfileId } | Select-Object -First 1
        Set-ActiveProfile $inactiveProfile.id
        if ($null -ne $IconUpdateCallback) {
            & $IconUpdateCallback
        }
        Load-Data
    })

    $quickViewForm.Controls.Add($dataGridView)
    $quickViewForm.Controls.Add($bottomPanel)

    $quickViewForm.Add_Deactivate({ $quickViewForm.Dispose() })
    $quickViewForm.Add_Shown({
        Load-Data
        $quickViewForm.Activate()
    })

    $quickViewForm.ShowDialog()
}