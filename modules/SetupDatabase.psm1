function SetupDatabase() {
    try {
        $dbConnection = New-SQLiteConnection -DataSource ".\GamingGaiden.db"

        # Shared tables
        $createGamesTableQuery = "CREATE TABLE IF NOT EXISTS games (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            name TEXT NOT NULL UNIQUE,
                            exe_name TEXT,
                            platform TEXT,
                            icon BLOB,
                            color_hex TEXT,
                            rom_based_name TEXT,
                            idle_detection BOOLEAN DEFAULT TRUE)"
        Invoke-SqliteQuery -Query $createGamesTableQuery -SQLiteConnection $dbConnection | Out-Null

        $createPlatformsTableQuery = "CREATE TABLE IF NOT EXISTS emulated_platforms (
                            name TEXT PRIMARY KEY NOT NULL,
                            exe_name TEXT,
                            core TEXT,
                            rom_extensions TEXT)"
        Invoke-SqliteQuery -Query $createPlatformsTableQuery -SQLiteConnection $dbConnection | Out-Null

        $createPCTableQuery = "CREATE TABLE IF NOT EXISTS gaming_pcs (
                            name TEXT PRIMARY KEY NOT NULL,
                            icon BLOB,
                            cost TEXT,
                            currency TEXT,
                            start_date INTEGER,
                            end_date INTEGER,
                            current TEXT)"
        Invoke-SqliteQuery -Query $createPCTableQuery -SQLiteConnection $dbConnection | Out-Null

        # Profile-specific tables
        $createProfilesTableQuery = "CREATE TABLE IF NOT EXISTS profiles (
                            id INTEGER PRIMARY KEY NOT NULL,
                            name TEXT NOT NULL,
                            is_active BOOLEAN NOT NULL)"
        Invoke-SqliteQuery -Query $createProfilesTableQuery -SQLiteConnection $dbConnection | Out-Null

        $profilesExist = Invoke-SqliteQuery -Query "SELECT COUNT(*) as '' FROM profiles" -SQLiteConnection $dbConnection
        if ($profilesExist.Column1 -eq 0) {
            $insertProfilesQuery = "INSERT INTO profiles (id, name, is_active) VALUES (1, 'Profile 1', 1), (2, 'Profile 2', 0)"
            Invoke-SqliteQuery -Query $insertProfilesQuery -SQLiteConnection $dbConnection | Out-Null
        }

        $createGameStatsTableQuery = "CREATE TABLE IF NOT EXISTS game_stats (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            game_id INTEGER NOT NULL,
                            profile_id INTEGER NOT NULL,
                            play_time INTEGER,
                            last_play_date INTEGER,
                            completed TEXT,
                            status TEXT,
                            session_count INTEGER,
                            idle_time INTEGER,
                            FOREIGN KEY(game_id) REFERENCES games(id),
                            FOREIGN KEY(profile_id) REFERENCES profiles(id))"
        Invoke-SqliteQuery -Query $createGameStatsTableQuery -SQLiteConnection $dbConnection | Out-Null

        $createDailyPlaytimeTableQuery = "CREATE TABLE IF NOT EXISTS daily_playtime (
                            play_date TEXT NOT NULL,
                            play_time INTEGER,
                            profile_id INTEGER NOT NULL,
                            PRIMARY KEY (play_date, profile_id))"
        Invoke-SqliteQuery -Query $createDailyPlaytimeTableQuery -SQLiteConnection $dbConnection | Out-Null

        $createSessionHistoryTableQuery = "CREATE TABLE IF NOT EXISTS session_history (
                                    game_name TEXT,
                                    session_start_time INTEGER,
                                    session_duration_minutes INTEGER,
                                    profile_id INTEGER NOT NULL
        )"
        Invoke-SqliteQuery -Query $createSessionHistoryTableQuery -SQLiteConnection $dbConnection | Out-Null

        # Migration for users coming from older versions
        $gamesTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('games')" -SQLiteConnection $dbConnection
        if ($gamesTableSchema.name.Contains("play_time")) {
            Log "Schema version 1 detected. Migrating to version 2."
            # 1. Rename old games table
            Invoke-SqliteQuery -Query "ALTER TABLE games RENAME TO games_old" -SQLiteConnection $dbConnection | Out-Null
            # 2. Create new games and game_stats tables
            Invoke-SqliteQuery -Query "CREATE TABLE IF NOT EXISTS games (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, exe_name TEXT, platform TEXT, icon BLOB, color_hex TEXT, rom_based_name TEXT)" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "CREATE TABLE IF NOT EXISTS game_stats (id INTEGER PRIMARY KEY AUTOINCREMENT, game_id INTEGER NOT NULL, profile_id INTEGER NOT NULL, play_time INTEGER, last_play_date INTEGER, completed TEXT, status TEXT, session_count INTEGER, idle_time INTEGER, disable_idle_detection BOOLEAN, FOREIGN KEY(game_id) REFERENCES games(id), FOREIGN KEY(profile_id) REFERENCES profiles(id))" -SQLiteConnection $dbConnection | Out-Null
            # 3. Migrate data
            Invoke-SqliteQuery -Query "INSERT INTO games (name, exe_name, platform, icon, color_hex, rom_based_name) SELECT name, exe_name, platform, icon, color_hex, rom_based_name FROM games_old" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "INSERT INTO game_stats (game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time, disable_idle_detection) SELECT g.id, 1, o.play_time, o.last_play_date, o.completed, o.status, o.session_count, o.idle_time, o.disable_idle_detection FROM games_old o JOIN games g ON o.name = g.name" -SQLiteConnection $dbConnection | Out-Null
            # 4. Drop old table
            Invoke-SqliteQuery -Query "DROP TABLE games_old" -SQLiteConnection $dbConnection | Out-Null
            Log "Migration to schema version 2 complete."
        }

        # Migration for idle_detection column rename
        $gameStatsTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('game_stats')" -SQLiteConnection $dbConnection
        if ($gameStatsTableSchema.name.Contains("disable_idle_detection")) {
            Log "Schema version 3 detected. Migrating to version 4."
            if (-Not $gameStatsTableSchema.name.Contains("idle_detection")) {
                Invoke-SqliteQuery -Query "ALTER TABLE game_stats ADD COLUMN idle_detection BOOLEAN DEFAULT TRUE" -SQLiteConnection $dbConnection | Out-Null
            }
            Invoke-SqliteQuery -Query "UPDATE game_stats SET idle_detection = (CASE WHEN disable_idle_detection = 1 THEN 0 ELSE 1 END)" -SQLiteConnection $dbConnection | Out-Null
            Log "Migration to schema version 4 complete."
        }

        # Migration to move idle_detection from game_stats to games
        $gameStatsTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('game_stats')" -SQLiteConnection $dbConnection
        $gamesTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('games')" -SQLiteConnection $dbConnection
        if ($gameStatsTableSchema.name.Contains("idle_detection") -or $gameStatsTableSchema.name.Contains("disable_idle_detection")) {
            Log "Schema version 4 detected. Migrating to version 5."
            if (-Not $gamesTableSchema.name.Contains("idle_detection")) {
                Invoke-SqliteQuery -Query "ALTER TABLE games ADD COLUMN idle_detection BOOLEAN DEFAULT TRUE" -SQLiteConnection $dbConnection | Out-Null
            }
            Invoke-SqliteQuery -Query "UPDATE games SET idle_detection = (SELECT idle_detection FROM game_stats WHERE game_stats.game_id = games.id AND profile_id = 1) WHERE EXISTS (SELECT 1 FROM game_stats WHERE game_stats.game_id = games.id AND profile_id = 1)" -SQLiteConnection $dbConnection | Out-Null

            Invoke-SqliteQuery -Query "ALTER TABLE game_stats RENAME TO game_stats_old" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query $createGameStatsTableQuery -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "INSERT INTO game_stats (id, game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time) SELECT id, game_id, profile_id, play_time, last_play_date, completed, status, session_count, idle_time FROM game_stats_old" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "DROP TABLE game_stats_old" -SQLiteConnection $dbConnection | Out-Null
            Log "Migration to schema version 5 complete."
        }

        # Add profile_id to session_history and daily_playtime if they don't have it
        $sessionHistoryTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('session_history')" -SQLiteConnection $dbConnection
        if (-Not $sessionHistoryTableSchema.name.Contains("profile_id")) {
            Invoke-SqliteQuery -Query "ALTER TABLE session_history ADD COLUMN profile_id INTEGER DEFAULT 1 NOT NULL" -SQLiteConnection $dbConnection | Out-Null
        }

        $dailyPlaytimeTableSchema = Invoke-SqliteQuery -query "PRAGMA table_info('daily_playtime')" -SQLiteConnection $dbConnection
        if (-Not $dailyPlaytimeTableSchema.name.Contains("profile_id")) {
             # This is tricky because of the composite primary key. We need to create a new table and copy data.
            Invoke-SqliteQuery -Query "ALTER TABLE daily_playtime RENAME TO daily_playtime_old" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query $createDailyPlaytimeTableQuery -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "INSERT INTO daily_playtime (play_date, play_time, profile_id) SELECT play_date, play_time, 1 FROM daily_playtime_old" -SQLiteConnection $dbConnection | Out-Null
            Invoke-SqliteQuery -Query "DROP TABLE daily_playtime_old" -SQLiteConnection $dbConnection | Out-Null
        }

        $dbConnection.Close()
        $dbConnection.Dispose()
    }
    catch {
        [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | out-null
        [System.Windows.Forms.MessageBox]::Show("Exception: $($_.Exception.Message). Check log for details", 'Gaming Gaiden', "OK", "Error")

        $timestamp = Get-date -f s
        Write-Output "$timestamp : Error: A user or system error has caused an exception. Database setup could not be finished. Check log for details." >> ".\GamingGaiden.log"
        Write-Output "$timestamp : Exception: $($_.Exception.Message)" >> ".\GamingGaiden.log"
        exit 1;
    }
}