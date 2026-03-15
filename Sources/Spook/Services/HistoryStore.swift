import Foundation
import SQLite3

actor HistoryStore {
    static let shared = HistoryStore()

    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        // Store in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let spookDir = appSupport.appendingPathComponent("Spook", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: spookDir, withIntermediateDirectories: true)

        dbPath = spookDir.appendingPathComponent("history.sqlite").path

        // Open database synchronously in init (nonisolated context)
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database at \(dbPath)")
        }

        // Create tables synchronously
        let createStatements = [
            """
            CREATE TABLE IF NOT EXISTS daily_totals (
                date TEXT PRIMARY KEY,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS app_daily_stats (
                date TEXT,
                process_name TEXT,
                display_name TEXT,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0,
                PRIMARY KEY (date, process_name)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS hourly_samples (
                timestamp INTEGER PRIMARY KEY,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0
            );
            """
        ]

        for sql in createStatements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
                if let errMsg = errMsg {
                    print("SQL error: \(String(cString: errMsg))")
                    sqlite3_free(errMsg)
                }
            }
        }
    }

    private nonisolated func openDatabaseSync(_ path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        if sqlite3_open(path, &database) != SQLITE_OK {
            print("Failed to open database at \(path)")
            return nil
        }
        return database
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database at \(dbPath)")
        }
    }

    private func createTables() {
        // Daily totals table
        let createDailyTotals = """
            CREATE TABLE IF NOT EXISTS daily_totals (
                date TEXT PRIMARY KEY,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0
            );
        """

        // Per-app daily stats
        let createAppStats = """
            CREATE TABLE IF NOT EXISTS app_daily_stats (
                date TEXT,
                process_name TEXT,
                display_name TEXT,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0,
                PRIMARY KEY (date, process_name)
            );
        """

        // Hourly samples for graphs (last 24 hours)
        let createHourlySamples = """
            CREATE TABLE IF NOT EXISTS hourly_samples (
                timestamp INTEGER PRIMARY KEY,
                bytes_in INTEGER DEFAULT 0,
                bytes_out INTEGER DEFAULT 0
            );
        """

        execute(createDailyTotals)
        execute(createAppStats)
        execute(createHourlySamples)
    }

    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Recording Data

    func recordTotals(bytesIn: Int64, bytesOut: Int64) {
        let today = dateString(Date())

        let sql = """
            INSERT INTO daily_totals (date, bytes_in, bytes_out)
            VALUES (?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, today, -1, nil)
            sqlite3_bind_int64(stmt, 2, bytesIn)
            sqlite3_bind_int64(stmt, 3, bytesOut)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func recordAppStats(_ apps: [AppTraffic]) {
        let today = dateString(Date())

        execute("BEGIN TRANSACTION;")

        let sql = """
            INSERT INTO app_daily_stats (date, process_name, display_name, bytes_in, bytes_out)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(date, process_name) DO UPDATE SET
                display_name = excluded.display_name,
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            execute("ROLLBACK;")
            return
        }

        for app in apps {
            let deltaIn = app.bytesIn - app.previousBytesIn
            let deltaOut = app.bytesOut - app.previousBytesOut

            guard deltaIn > 0 || deltaOut > 0 else { continue }

            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text(stmt, 1, today, -1, nil)
            sqlite3_bind_text(stmt, 2, app.processName, -1, nil)
            sqlite3_bind_text(stmt, 3, app.displayName, -1, nil)
            sqlite3_bind_int64(stmt, 4, deltaIn)
            sqlite3_bind_int64(stmt, 5, deltaOut)
            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt)
                execute("ROLLBACK;")
                return
            }
        }

        sqlite3_finalize(stmt)
        execute("COMMIT;")
    }

    func recordHourlySample(bytesIn: Int64, bytesOut: Int64) {
        let hour = hourTimestamp(Date())

        let sql = """
            INSERT INTO hourly_samples (timestamp, bytes_in, bytes_out)
            VALUES (?, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(hour))
            sqlite3_bind_int64(stmt, 2, bytesIn)
            sqlite3_bind_int64(stmt, 3, bytesOut)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Querying Data

    func getDailyTotals(for date: Date) -> (bytesIn: Int64, bytesOut: Int64) {
        let dateStr = dateString(date)

        let sql = "SELECT bytes_in, bytes_out FROM daily_totals WHERE date = ?;"

        var stmt: OpaquePointer?
        var result: (Int64, Int64) = (0, 0)

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateStr, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                result.0 = sqlite3_column_int64(stmt, 0)
                result.1 = sqlite3_column_int64(stmt, 1)
            }
        }
        sqlite3_finalize(stmt)

        return result
    }

    func getWeeklyTotals() -> (bytesIn: Int64, bytesOut: Int64) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let weekAgoStr = dateString(weekAgo)

        let sql = "SELECT SUM(bytes_in), SUM(bytes_out) FROM daily_totals WHERE date >= ?;"

        var stmt: OpaquePointer?
        var result: (Int64, Int64) = (0, 0)

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, weekAgoStr, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                result.0 = sqlite3_column_int64(stmt, 0)
                result.1 = sqlite3_column_int64(stmt, 1)
            }
        }
        sqlite3_finalize(stmt)

        return result
    }

    func getHourlySamples(hours: Int = 24) -> [(timestamp: Date, bytesIn: Int64, bytesOut: Int64)] {
        let cutoff = hourTimestamp(Date()) - (hours * 3600)

        let sql = """
            SELECT timestamp, bytes_in, bytes_out
            FROM hourly_samples
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
        """

        var stmt: OpaquePointer?
        var results: [(Date, Int64, Int64)] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(cutoff))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)))
                let bytesIn = sqlite3_column_int64(stmt, 1)
                let bytesOut = sqlite3_column_int64(stmt, 2)
                results.append((timestamp, bytesIn, bytesOut))
            }
        }
        sqlite3_finalize(stmt)

        return results
    }

    func getTopApps(for date: Date, limit: Int = 10) -> [(processName: String, displayName: String, bytesIn: Int64, bytesOut: Int64)] {
        let dateStr = dateString(date)

        let sql = """
            SELECT process_name, display_name, bytes_in, bytes_out
            FROM app_daily_stats
            WHERE date = ?
            ORDER BY (bytes_in + bytes_out) DESC
            LIMIT ?;
        """

        var stmt: OpaquePointer?
        var results: [(String, String, Int64, Int64)] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateStr, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let processName = String(cString: sqlite3_column_text(stmt, 0))
                let displayName = String(cString: sqlite3_column_text(stmt, 1))
                let bytesIn = sqlite3_column_int64(stmt, 2)
                let bytesOut = sqlite3_column_int64(stmt, 3)
                results.append((processName, displayName, bytesIn, bytesOut))
            }
        }
        sqlite3_finalize(stmt)

        return results
    }

    // MARK: - Maintenance

    func pruneOldData(daysToKeep: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date())!
        let cutoffStr = dateString(cutoff)

        // Use parameterized queries to prevent SQL injection
        let tables = ["daily_totals", "app_daily_stats"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE date < ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoffStr, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        // Keep only 7 days of hourly samples
        let hourlyCutoff = hourTimestamp(Date()) - (7 * 24 * 3600)
        let hourlySql = "DELETE FROM hourly_samples WHERE timestamp < ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, hourlySql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(hourlyCutoff))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func clearAllHistory() {
        execute("DELETE FROM daily_totals;")
        execute("DELETE FROM app_daily_stats;")
        execute("DELETE FROM hourly_samples;")
    }

    // MARK: - Helpers

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func hourTimestamp(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let hourDate = calendar.date(from: components)!
        return Int(hourDate.timeIntervalSince1970)
    }

    deinit {
        sqlite3_close(db)
    }
}
