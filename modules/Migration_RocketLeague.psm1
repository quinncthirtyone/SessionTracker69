function Invoke-RocketLeagueMigration {
    try {
        $dbConnection = New-SQLiteConnection -DataSource ".\GamingGaiden.db"

        # Check if the migration is needed
        $checkGameQuery = "SELECT * FROM games WHERE name = 'Rocket League'"
        $game = Invoke-SqliteQuery -Query $checkGameQuery -SQLiteConnection $dbConnection

        if ($game) {
            Log "Rocket League migration already completed. Skipping."
            $dbConnection.Close()
            $dbConnection.Dispose()
            return
        }

        Log "Running Rocket League migration..."

        # Update games table
        $updateGamesQuery = "UPDATE games SET name = 'Rocket League' WHERE name = 'RocketLeague'"
        Invoke-SqliteQuery -Query $updateGamesQuery -SQLiteConnection $dbConnection | Out-Null

        # Update session_history table
        $updateSessionHistoryQuery = "UPDATE session_history SET game_name = 'Rocket League' WHERE game_name = 'RocketLeague'"
        Invoke-SqliteQuery -Query $updateSessionHistoryQuery -SQLiteConnection $dbConnection | Out-Null

        Log "Rocket League migration completed successfully."

        $dbConnection.Close()
        $dbConnection.Dispose()
    }
    catch {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | out-null
        [System.Windows.Forms.MessageBox]::Show("Exception: $($_.Exception.Message). Check log for details", 'Gaming Gaiden', "OK", "Error")

        $timestamp = Get-date -f s
        Write-Output "$timestamp : Error: A user or system error has caused an exception. Rocket League migration could not be finished. Check log for details." >> ".\GamingGaiden.log"
        Write-Output "$timestamp : Exception: $($_.Exception.Message)" >> ".\GamingGaiden.log"
        exit 1;
    }
}
