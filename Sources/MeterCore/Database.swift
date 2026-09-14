import Foundation
import CSQLite

public final class Database {
    private var db: OpaquePointer?
    public let directory: URL
    public static var defaultDirectory: URL {
        if let custom=ProcessInfo.processInfo.environment["CODEX_METER_HOME"], !custom.isEmpty { return URL(fileURLWithPath:custom) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexMeter")
    }
    public init(directory: URL = Database.defaultDirectory) throws {
        self.directory=directory
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard sqlite3_open_v2(directory.appendingPathComponent("meter.sqlite").path,&db,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else { throw MeterError("Не удалось открыть базу Codex Meter") }
        sqlite3_busy_timeout(db,5000)
        try exec("PRAGMA journal_mode=WAL")
        try exec("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try exec("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
        try exec("CREATE TABLE IF NOT EXISTS turns (id TEXT PRIMARY KEY, thread TEXT NOT NULL, task_id TEXT, started REAL NOT NULL, data TEXT NOT NULL)")
        try exec("CREATE INDEX IF NOT EXISTS turns_thread ON turns(thread)")
        try exec("CREATE TABLE IF NOT EXISTS bindings (thread TEXT NOT NULL, turn TEXT NOT NULL, task_id TEXT NOT NULL, PRIMARY KEY(thread,turn))")
        try exec("CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL, data TEXT NOT NULL)")
        try exec("CREATE TABLE IF NOT EXISTS observations (id INTEGER PRIMARY KEY, account TEXT NOT NULL, stamp REAL NOT NULL, data TEXT NOT NULL)")
        try exec("CREATE INDEX IF NOT EXISTS observations_stamp ON observations(stamp)")
        try exec("PRAGMA user_version=1")
    }
    deinit { sqlite3_close(db) }
    public func exec(_ sql: String, _ params: [Any?] = []) throws { _ = try query(sql,params) }
    public func query(_ sql: String, _ params: [Any?] = []) throws -> [[String:String]] {
        var stmt:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(stmt) }
        let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        for (i,p) in params.enumerated() {
            let index=Int32(i+1)
            if let v=p as? String { sqlite3_bind_text(stmt,index,v,-1,transient) }
            else if let v=p as? Double { sqlite3_bind_double(stmt,index,v) }
            else if let v=p as? Int { sqlite3_bind_int64(stmt,index,Int64(v)) }
            else { sqlite3_bind_null(stmt,index) }
        }
        var rows:[[String:String]]=[]
        while true {
            let step=sqlite3_step(stmt)
            if step==SQLITE_DONE { return rows }
            guard step==SQLITE_ROW else { throw error() }
            var row:[String:String]=[:]
            for col in 0..<sqlite3_column_count(stmt) {
                if let key=sqlite3_column_name(stmt,col),let value=sqlite3_column_text(stmt,col) { row[String(cString:key)]=String(cString:value) }
            }
            rows.append(row)
        }
    }
    private func error() -> MeterError { MeterError(db.map { String(cString:sqlite3_errmsg($0)) } ?? "Ошибка SQLite") }
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        let outermost=sqlite3_get_autocommit(db) != 0
        let name="tx_"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
        try exec(outermost ? "BEGIN IMMEDIATE":"SAVEPOINT \(name)")
        do { let result=try body();try exec(outermost ? "COMMIT":"RELEASE \(name)");return result }
        catch {
            if outermost {try? exec("ROLLBACK")}
            else {try? exec("ROLLBACK TO \(name)");try? exec("RELEASE \(name)")}
            throw error
        }
    }

    public func value(_ key: String) throws -> String? { try query("SELECT value FROM kv WHERE key=?",[key]).first?["value"] }
    public func set(_ key: String, _ value: String) throws { try exec("INSERT INTO kv VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",[key,value]) }
    public func saveTask(_ task: WorkTask) throws { try exec("INSERT INTO tasks VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",[task.id,try Codec.encode(task)]) }
    public func tasks() throws -> [WorkTask] { try query("SELECT data FROM tasks").map { try Codec.decode(WorkTask.self,$0["data"]!) }.sorted { $0.created > $1.created } }
    public func task(_ id: String) throws -> WorkTask? { try query("SELECT data FROM tasks WHERE id=?",[id]).first.map { try Codec.decode(WorkTask.self,$0["data"]!) } }
    public func bind(thread: String, turn: String, task: String) throws {
        guard try self.task(task) != nil else { throw MeterError("Задача не найдена") }
        try exec("INSERT INTO bindings VALUES (?,?,?) ON CONFLICT(thread,turn) DO UPDATE SET task_id=excluded.task_id",[thread,turn,task])
        try exec("UPDATE turns SET task_id=? WHERE id=? AND thread=?",[task,turn,thread])
    }
    public func activeTask(thread: String) throws -> WorkTask? {
        guard let id=try value("active:\(thread)"), let task=try task(id), ["active","paused"].contains(task.status) else { return nil }
        return task
    }
    public func saveRun(_ run: RunRecord) throws {
        // Forked transcripts can replay ancestral turns; keep the original owner.
        if let existing=try query("SELECT thread FROM turns WHERE id=?",[run.id]).first?["thread"],existing != run.thread {return}
        let binding=try query("SELECT task_id FROM bindings WHERE thread=? AND turn=?",[run.thread,run.id]).first?["task_id"]
        try exec("INSERT INTO turns VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data, task_id=COALESCE(excluded.task_id,turns.task_id)",[run.id,run.thread,binding ?? run.taskID,run.started.timeIntervalSince1970,try Codec.encode(run)])
    }
    public func runs() throws -> [RunRecord] {
        try query("SELECT data,task_id FROM turns ORDER BY started DESC").map { row in
            var run=try Codec.decode(RunRecord.self,row["data"]!);run.taskID=row["task_id"];return run
        }
    }
    public func savePayment(_ payment: Payment) throws {
        guard payment.amount > 0, payment.amount.isFinite, payment.seconds >= 86400 else { throw MeterError("Укажите положительную сумму и период не короче суток") }
        try transaction {
            guard try query("SELECT id FROM payments WHERE id<>? AND start<? AND end>?",[payment.id,payment.end.timeIntervalSince1970,payment.start.timeIntervalSince1970]).isEmpty else { throw MeterError("Период пересекается с уже внесённым платежом") }
            try exec("INSERT INTO payments VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET start=excluded.start,end=excluded.end,data=excluded.data",[payment.id,payment.start.timeIntervalSince1970,payment.end.timeIntervalSince1970,try Codec.encode(payment)])
        }
    }
    public func payments() throws -> [Payment] { try query("SELECT data FROM payments ORDER BY start DESC").map { try Codec.decode(Payment.self,$0["data"]!) } }
    public func snapshot() throws -> AccountSnapshot? { try value("snapshot").map { try Codec.decode(AccountSnapshot.self,$0) } }
    public func alertKey(account:String,bucket:String,window:QuotaWindow) throws -> String {
        let anchorKey="alertAnchor:\(account):\(bucket):\(window.windowDurationMins ?? 0)"
        var stable=window
        if let reset=window.resetsAt {
            if let raw=try value(anchorKey),let anchor=Double(raw),abs(anchor-reset)<=90 {stable.resetsAt=anchor}
            else {try set(anchorKey,String(reset))}
        }
        return AlertPolicy.key(account:account,bucket:bucket,window:stable)
    }
    public func saveSnapshot(_ snapshot: AccountSnapshot) throws {
        try transaction {
            try set("snapshot",try Codec.encode(snapshot))
            if let window=snapshot.moneyWindow {
                let observation=QuotaObservation(account:snapshot.accountKey,date:snapshot.fetchedAt,window:window)
                try exec("INSERT INTO observations(account,stamp,data) VALUES (?,?,?)",[snapshot.accountKey,snapshot.fetchedAt.timeIntervalSince1970,try Codec.encode(observation)])
            }
        }
    }
    public func observations() throws -> [QuotaObservation] { try query("SELECT data FROM observations ORDER BY stamp").map { try Codec.decode(QuotaObservation.self,$0["data"]!) } }
    public func mergeTasks(source: String, target: String) throws {
        guard source != target, try task(source) != nil, try task(target) != nil else { throw MeterError("Выберите две разные задачи") }
        try transaction {
            try exec("UPDATE turns SET task_id=? WHERE task_id=?",[target,source])
            try exec("UPDATE bindings SET task_id=? WHERE task_id=?",[target,source])
            try exec("UPDATE kv SET value=? WHERE key LIKE 'active:%' AND value=?",[target,source])
            try exec("DELETE FROM tasks WHERE id=?",[source])
        }
    }
    public func summaries() throws -> [TaskSummary] {
        let allRuns=try runs(), allTasks=try tasks(), obs=try observations(), bills=try payments()
        let attribution=Attribution.compute(runs:allRuns,observations:obs,payments:bills)
        return allTasks.map { task in
            let runs=allRuns.filter { $0.taskID==task.id }, a=attribution[task.id]
            return TaskSummary(task:task,runs:runs,quotaPoints:a?.points,rubles:a?.rubles,quotaQuality:a?.quality ?? "Нет измерения квоты",measuredRubles:a?.measuredRubles,costCoverage:a?.costCoverage,weeklyQuota:a?.weeklyQuota)
        }
    }
}
