import Foundation

public enum Journal {
    private static func tokens(_ dict:[String:Any]) -> TokenCount {
        .init(input:(dict["input_tokens"] as? NSNumber)?.int64Value ?? 0,cached:(dict["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0,output:(dict["output_tokens"] as? NSNumber)?.int64Value ?? 0,reasoning:(dict["reasoning_output_tokens"] as? NSNumber)?.int64Value ?? 0)
    }
    public static func parse(_ data:Data, fallbackThread:String) -> [RunRecord] {
        let precise=ISO8601DateFormatter();precise.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let whole=ISO8601DateFormatter()
        func date(_ value:Any?) -> Date? {guard let value=value as? String else{return nil};return precise.date(from:value) ?? whole.date(from:value)}
        var thread=fallbackThread,parent:String?,active:String?,model="",effort=""
        var baseline=TokenCount(),runs:[String:RunRecord]=[:]
        // Only complete JSONL lines: a writer can be in the middle of its final line.
        let lines=data.split(separator:10,omittingEmptySubsequences:false)
        for line in lines.dropLast() {
            guard let row=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any],
                  let p=row["payload"] as? [String:Any],let timestamp=date(row["timestamp"]) else { continue }
            let type=row["type"] as? String
            if type=="session_meta" {
                thread=p["id"] as? String ?? thread
                if let source=p["source"] as? [String:Any],let sub=source["subagent"] as? [String:Any],let spawn=sub["thread_spawn"] as? [String:Any] { parent=spawn["parent_thread_id"] as? String }
            } else if type=="turn_context" {
                model=p["model"] as? String ?? model;effort=p["effort"] as? String ?? effort
                if let id=active,var run=runs[id] { run.model=model;run.effort=effort;runs[id]=run }
            } else if type=="event_msg" {
                switch p["type"] as? String {
                case "task_started":
                    guard let id=p["turn_id"] as? String else { continue }
                    // A new turn closes an interrupted predecessor, not its user task.
                    if let previous=active,var old=runs[previous],old.ended==nil { old.ended=timestamp;old.outcome="interrupted";runs[previous]=old }
                    active=id
                    if runs[id]==nil { runs[id]=RunRecord(id:id,thread:thread,parentThread:parent,started:date(p["started_at"]) ?? timestamp,model:model,effort:effort) }
                case "user_message":
                    if let id=active,var run=runs[id],let message=p["message"] as? String,run.title=="Запуск Codex" {
                        let first=message.split(separator:"\n").first.map(String.init) ?? "Запуск Codex"
                        if !first.hasPrefix("<") { run.title=String(first.prefix(100)) };runs[id]=run
                    }
                case "token_count":
                    guard let info=p["info"] as? [String:Any],let total=info["total_token_usage"] as? [String:Any] else { continue }
                    let next=tokens(total),delta=next.delta(from:baseline);baseline=next
                    if let id=active,var run=runs[id],delta.total>0 {
                        run.tokens=run.tokens+delta;run.tokenEvents.append(TokenEvent(date:timestamp,tokens:delta));runs[id]=run
                    }
                case "task_complete":
                    let id=p["turn_id"] as? String ?? active
                    if let id,var run=runs[id] { run.ended=date(p["completed_at"]) ?? timestamp;run.outcome="completed";runs[id]=run }
                    if id==active { active=nil }
                case "turn_aborted":
                    if let id=active,var run=runs[id] { run.ended=timestamp;run.outcome="interrupted";runs[id]=run };active=nil
                default:break
                }
            }
        }
        let transcript=Transcript.parse(data)
        for turn in transcript.turns {
            guard var run=runs[turn.id] else{continue}
            run.workingDirectory=transcript.workingDirectory;run.category=transcript.category
            run.messageCount=turn.messages.count
            run.title=transcript.category=="service" ? "Автоматическая проверка действия Codex":turn.title
            run.preview=turn.messages.first(where:{$0.role=="assistant" && ["final_answer","final"].contains($0.phase ?? "")}).map{String($0.text.prefix(240))}
                ?? turn.messages.first(where:{$0.role=="assistant"}).map{String($0.text.prefix(240))}
            runs[turn.id]=run
        }
        return runs.values.sorted{$0.started<$1.started}
    }
    public static func sync(db:Database,home:URL? = nil) throws -> Int {
        let root=home ?? URL(fileURLWithPath:ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        var changed=0
        for subdir in ["sessions","archived_sessions"] {
            guard let enumerator=FileManager.default.enumerator(at:root.appendingPathComponent(subdir),includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles]) else { continue }
            for case let path as URL in enumerator where path.pathExtension=="jsonl" {
                let values=try path.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                let fingerprint="transcript-v2:\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                let key="file:\(path.path)"
                guard try db.value(key) != fingerprint else { continue }
                let parsed=parse(try Data(contentsOf:path,options:.mappedIfSafe),fallbackThread:path.deletingPathExtension().lastPathComponent)
                try db.transaction {
                    for var run in parsed {
                        run.sourcePath=path.path
                        // A crashed process should not appear to run forever.
                        if run.ended==nil,Date().timeIntervalSince(values.contentModificationDate ?? Date())>3600 {
                            run.ended=run.tokenEvents.last?.date ?? run.started;run.outcome="interrupted"
                        }
                        try db.saveRun(run)
                    }
                    try db.set(key,fingerprint)
                }
                changed += 1
            }
        }
        // Attribute child-agent turns only when the parent has a single matching task.
        let all=try db.runs()
        for run in all where run.taskID==nil && run.parentThread != nil {
            let parents=all.filter{$0.thread==run.parentThread! && $0.taskID != nil && $0.started<=run.started && ($0.ended ?? Date())>=run.started}
            let ids=Set(parents.compactMap(\.taskID))
            if ids.count==1,let task=ids.first { try db.bind(thread:run.thread,turn:run.id,task:task) }
        }
        return changed
    }
}
