import Foundation
import SQLite3

actor HistoryStore {
    static let shared = HistoryStore()

    private var db: OpaquePointer?
    private let dbPath: String

    // Cached formatter — avoid allocating one per write. ponytail: also avoids repeated Calendar work below where cheap.
    private let dayFormatter: DateFormatter

    // In-memory accumulators, flushed to disk periodically (see flush()).
    private var pendingDailyTotals: [String: (bytesIn: Int64, bytesOut: Int64)] = [:]
    private var pendingHourlySamples: [Int: (bytesIn: Int64, bytesOut: Int64)] = [:]
    private var pendingAppStats: [String: (date: String, processName: String, displayName: String, bytesIn: Int64, bytesOut: Int64)] = [:]

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        dayFormatter = formatter

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

        // Enable WAL so concurrent readers don't block on the periodic write transaction.
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
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

    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Recording Data (in-memory only — see flush())

    func recordTotals(bytesIn: Int64, bytesOut: Int64) {
        let today = dateString(Date())
        let existing = pendingDailyTotals[today] ?? (0, 0)
        pendingDailyTotals[today] = (existing.bytesIn + bytesIn, existing.bytesOut + bytesOut)
    }

    func recordAppStats(_ apps: [AppTraffic]) {
        let today = dateString(Date())

        for app in apps {
            let deltaIn = app.bytesIn - app.previousBytesIn
            let deltaOut = app.bytesOut - app.previousBytesOut

            guard deltaIn > 0 || deltaOut > 0 else { continue }

            let key = "\(today)|\(app.processName)"
            if let existing = pendingAppStats[key] {
                pendingAppStats[key] = (today, app.processName, app.displayName, existing.bytesIn + deltaIn, existing.bytesOut + deltaOut)
            } else {
                pendingAppStats[key] = (today, app.processName, app.displayName, deltaIn, deltaOut)
            }
        }
    }

    func recordHourlySample(bytesIn: Int64, bytesOut: Int64) {
        let hour = hourTimestamp(Date())
        let existing = pendingHourlySamples[hour] ?? (0, 0)
        pendingHourlySamples[hour] = (existing.bytesIn + bytesIn, existing.bytesOut + bytesOut)
    }

    // MARK: - Flushing

    /// Writes all pending in-memory data to disk in a single transaction and clears the accumulators.
    func flush() {
        guard !pendingDailyTotals.isEmpty || !pendingHourlySamples.isEmpty || !pendingAppStats.isEmpty else {
            return
        }

        execute("BEGIN TRANSACTION;")

        let dailyTotalsSql = """
            INSERT INTO daily_totals (date, bytes_in, bytes_out)
            VALUES (?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """
        var dailyStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, dailyTotalsSql, -1, &dailyStmt, nil) == SQLITE_OK {
            for (date, totals) in pendingDailyTotals {
                sqlite3_reset(dailyStmt)
                sqlite3_clear_bindings(dailyStmt)
                sqlite3_bind_text(dailyStmt, 1, date, -1, nil)
                sqlite3_bind_int64(dailyStmt, 2, totals.bytesIn)
                sqlite3_bind_int64(dailyStmt, 3, totals.bytesOut)
                sqlite3_step(dailyStmt)
            }
        }
        sqlite3_finalize(dailyStmt)

        let hourlySql = """
            INSERT INTO hourly_samples (timestamp, bytes_in, bytes_out)
            VALUES (?, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """
        var hourlyStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, hourlySql, -1, &hourlyStmt, nil) == SQLITE_OK {
            for (timestamp, totals) in pendingHourlySamples {
                sqlite3_reset(hourlyStmt)
                sqlite3_clear_bindings(hourlyStmt)
                sqlite3_bind_int64(hourlyStmt, 1, Int64(timestamp))
                sqlite3_bind_int64(hourlyStmt, 2, totals.bytesIn)
                sqlite3_bind_int64(hourlyStmt, 3, totals.bytesOut)
                sqlite3_step(hourlyStmt)
            }
        }
        sqlite3_finalize(hourlyStmt)

        let appStatsSql = """
            INSERT INTO app_daily_stats (date, process_name, display_name, bytes_in, bytes_out)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(date, process_name) DO UPDATE SET
                display_name = excluded.display_name,
                bytes_in = bytes_in + excluded.bytes_in,
                bytes_out = bytes_out + excluded.bytes_out;
        """
        var appStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, appStatsSql, -1, &appStmt, nil) == SQLITE_OK {
            for (_, entry) in pendingAppStats {
                sqlite3_reset(appStmt)
                sqlite3_clear_bindings(appStmt)
                sqlite3_bind_text(appStmt, 1, entry.date, -1, nil)
                sqlite3_bind_text(appStmt, 2, entry.processName, -1, nil)
                sqlite3_bind_text(appStmt, 3, entry.displayName, -1, nil)
                sqlite3_bind_int64(appStmt, 4, entry.bytesIn)
                sqlite3_bind_int64(appStmt, 5, entry.bytesOut)
                sqlite3_step(appStmt)
            }
        }
        sqlite3_finalize(appStmt)

        execute("COMMIT;")

        pendingDailyTotals.removeAll()
        pendingHourlySamples.removeAll()
        pendingAppStats.removeAll()
    }

    // MARK: - Querying Data

    func getDailyTotals(for date: Date) -> (bytesIn: Int64, bytesOut: Int64) {
        flush()
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
        flush()
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
        flush()
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
        flush()
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
        flush()
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
        pendingDailyTotals.removeAll()
        pendingHourlySamples.removeAll()
        pendingAppStats.removeAll()
        execute("DELETE FROM daily_totals;")
        execute("DELETE FROM app_daily_stats;")
        execute("DELETE FROM hourly_samples;")
    }

    // MARK: - Helpers

    private func dateString(_ date: Date) -> String {
        dayFormatter.string(from: date)
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
