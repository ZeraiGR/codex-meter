import Foundation

public enum Commands {
    public static let help="""
    Codex Meter — local subscription and task accounting
    status                         Cached quota (JSON; no model requests)
    refresh                        Refresh account limits and daily history
    sync                           Import local token events
    tasks                          List user tasks and their metrics
    task-start --thread ID --turn ID --title TEXT --kind TYPE [--skill-version HASH]
    task-resume --id ID --thread ID --turn ID
    task-end --id ID [--outcome completed|cancelled|failed]
    task-pause --id ID
    task-assign --id ID --thread ID --turn ID
    task-merge --source ID --target ID
    forecast --kind TYPE [--model MODEL]
    payment --amount RUB --start YYYY-MM-DD --end YYYY-MM-DD
    hook                           UserPromptSubmit hook; reads JSON stdin
    """
    public static func run(_ args:[String],directory:URL? = nil,input:Data? = nil) throws -> String {
        guard let command=args.first else{return help}
        if ["--help","help","-h"].contains(command) {return help}
        let db=try Database(directory:directory ?? Database.defaultDirectory)
        func option(_ key:String) -> String? {
            guard let index=args.firstIndex(of:"--"+key),index+1<args.count else{return nil}
            return args[index+1]
        }
        func required(_ key:String) throws -> String {
            guard let value=option(key),!value.isEmpty else{throw MeterError("Нужен параметр --\(key)")};return value
        }
        switch command {
        case "status":return try db.snapshot().map{try Codec.encode($0)} ?? "{\"status\":\"no_data\"}"
        case "refresh":
            let snapshot=try CodexClient.fetch(db:db);try db.saveSnapshot(snapshot);return try Codec.encode(snapshot)
        case "sync":return "{\"updatedFiles\":\(try Journal.sync(db:db))}"
        case "tasks":
            let values=try db.summaries().map { s -> [String:Any] in
                ["id":s.id,"title":s.task.title,"kind":s.task.kind,"status":s.task.status,"tokens":s.tokens.total,"seconds":s.activeSeconds,"quotaPoints":s.quotaPoints as Any? ?? NSNull(),"rubles":s.rubles as Any? ?? NSNull(),"quality":s.quotaQuality,"measuredRubles":s.measuredRubles as Any? ?? NSNull(),"costCoverage":s.costCoverage as Any? ?? NSNull(),"projectedRubles":s.projectedRubles as Any? ?? NSNull(),"weeklyQuota":s.weeklyQuota.map{["points":$0.points,"coverage":$0.coverage,"windowCount":$0.windowCount] as [String:Any]} as Any? ?? NSNull()]
            }
            return String(decoding:try JSONSerialization.data(withJSONObject:values,options:[.sortedKeys]),as:UTF8.self)
        case "task-start":
            let thread=try required("thread"),turn=try required("turn"),title=try required("title"),kind=try required("kind")
            let task:WorkTask=try db.transaction {
                if var active=try db.activeTask(thread:thread) {
                    if active.title==title && active.kind==kind {
                        active.status="active";try db.saveTask(active);try db.bind(thread:thread,turn:turn,task:active.id);return active
                    }
                    active.status="paused";try db.saveTask(active)
                }
                let task=WorkTask(title:title,kind:kind,skillVersion:option("skill-version"))
                try db.saveTask(task);try db.bind(thread:thread,turn:turn,task:task.id);try db.set("active:\(thread)",task.id)
                return task
            }
            return try Codec.encode(task)
        case "task-resume":
            let id=try required("id"),thread=try required("thread"),turn=try required("turn")
            guard var task=try db.task(id) else{throw MeterError("Задача не найдена")}
            try db.transaction {
                if var previous=try db.activeTask(thread:thread),previous.id != id {previous.status="paused";try db.saveTask(previous)}
                task.status="active";task.finished=nil;try db.saveTask(task);try db.bind(thread:thread,turn:turn,task:id);try db.set("active:\(thread)",id)
            }
            return try Codec.encode(task)
        case "task-end","task-pause":
            let id=try required("id")
            guard var task=try db.task(id) else{throw MeterError("Задача не найдена")}
            let outcome=command=="task-pause" ? "paused":option("outcome") ?? "completed"
            guard ["paused","completed","cancelled","failed"].contains(outcome) else{throw MeterError("Неизвестный результат задачи")}
            task.status=outcome;task.finished=outcome=="paused" ? nil:Date();try db.saveTask(task)
            return try Codec.encode(task)
        case "task-assign":try db.bind(thread:required("thread"),turn:required("turn"),task:required("id"));return "{\"ok\":true}"
        case "task-merge":try db.mergeTasks(source:required("source"),target:required("target"));return "{\"ok\":true}"
        case "forecast":
            let snapshot=try db.snapshot(),payment=try db.payments().first{$0.contains(Date())}
            return try Codec.encode(Predictor.estimate(kind:required("kind"),history:db.summaries(),snapshot:snapshot,payment:payment,model:option("model")))
        case "payment":
            let fmt=DateFormatter();fmt.locale=Locale(identifier:"en_US_POSIX");fmt.dateFormat="yyyy-MM-dd";fmt.isLenient=false
            guard let amount=Double(try required("amount").replacingOccurrences(of:",",with:".")),let start=fmt.date(from:try required("start")),let end=fmt.date(from:try required("end")) else {throw MeterError("Проверьте сумму и даты YYYY-MM-DD")}
            let payment=Payment(amount:amount,start:start,end:end);try db.savePayment(payment);return try Codec.encode(payment)
        case "hook":return try hook(db:db,input:input ?? FileHandle.standardInput.readDataToEndOfFile())
        default:throw MeterError("Неизвестная команда. Используйте --help")
        }
    }
    private static func hook(db:Database,input:Data) throws -> String {
        guard let event=try JSONSerialization.jsonObject(with:input) as? [String:Any],let thread=event["session_id"] as? String,let turn=event["turn_id"] as? String else{return "{}"}
        let active=try db.activeTask(thread:thread)
        if let active {try db.bind(thread:thread,turn:turn,task:active.id)}
        let binary=Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        var context="""
        Codex Meter tracks user-level tasks locally. Current thread=\(thread), turn=\(turn).
        CLI executable: \(binary). Quote paths/arguments safely.
        For work performed with a skill, automatically call task-start --thread <thread> --turn <turn> --title <specific user outcome> --kind <skill-name> before substantial work, then forecast --kind <skill-name> --model <current model>. Warn concisely if risk is high/caution; never promise sufficient quota when unknown. Tracking failure must not block user work.
        For other work, start tracking when the user asks to start a task (e.g. «начинаем задачу …»). Reuse the same task for clarifications/retries/continuations; a response ending is not task completion. task-pause --id ID when waiting for user input; task-end --id ID only when the intended outcome is delivered (or --outcome cancelled/failed). Use task-resume --id ID --thread <thread> --turn <turn> to continue across sessions. Child agents belong to their parent's task, not new tasks. Do not start a task solely for a nested helper skill.
        """
        if let active {context += "\nExisting task: \(active.id); kind=\(active.kind); title=\(active.title). Continue it unless the user starts a distinct task."}
        if let snapshot=try db.snapshot(),snapshot.fresh(),let window=snapshot.moneyWindow,window.valid(at:Date()) {
            context += "\nCached remaining main quota: \(Int(window.remaining))%, window \(window.label). This is quota, not a remaining token count."
        }
        let response:[String:Any]=["hookSpecificOutput":["hookEventName":"UserPromptSubmit","additionalContext":context]]
        return String(decoding:try JSONSerialization.data(withJSONObject:response),as:UTF8.self)
    }
}
