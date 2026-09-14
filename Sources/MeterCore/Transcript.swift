import Foundation

public struct TranscriptMessage: Identifiable, Sendable {
    public var id: String
    public var role: String
    public var text: String
    public var date: Date
    public var phase: String?
}
public struct TranscriptTurn: Identifiable, Sendable {
    public var id: String
    public var messages: [TranscriptMessage]
    public var date: Date
    public var title: String { Transcript.title(messages.first(where:{$0.role=="user"})?.text ?? "") }
}
public struct TranscriptDocument: Sendable {
    public var turns: [TranscriptTurn]
    public var workingDirectory: String?
    public var category: String
}

public enum Transcript {
    public static func title(_ text: String) -> String {
        let clean=text.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        return clean.isEmpty ? "Продолжение без нового запроса":String(clean.prefix(180))
    }
    /// Remove transport-only wrappers, preserving the user's own text and code.
    public static func userText(_ text:String) -> String {
        var value=text
        for tag in ["environment_context","permissions instructions","skills_instructions"] {
            value=value.replacingOccurrences(of:"(?s)<"+NSRegularExpression.escapedPattern(for:tag)+"(?:\\s[^>]*)?>.*?</"+NSRegularExpression.escapedPattern(for:tag)+">",with:"",options:.regularExpression)
        }
        if value.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("# AGENTS.md instructions for") { return "" }
        value=value.replacingOccurrences(of:"(?s)<image\\b[^>]*>.*?</image>",with:"[Изображение]",options:.regularExpression)
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    public static func parse(_ data:Data) -> TranscriptDocument {
        let precise=ISO8601DateFormatter();precise.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let whole=ISO8601DateFormatter()
        var cwd:String?,category="conversation",active:String?,order:[String]=[]
        var dates:[String:Date]=[:],canonical:[String:[TranscriptMessage]]=[:],fallback:[String:[TranscriptMessage]]=[:]
        for (index,line) in data.split(separator:10,omittingEmptySubsequences:false).dropLast().enumerated() {
            guard let row=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let p=row["payload"] as? [String:Any] else{continue}
            let kind=row["type"] as? String,type=p["type"] as? String
            let rawDate=row["timestamp"] as? String ?? ""
            let date=precise.date(from:rawDate) ?? whole.date(from:rawDate) ?? .distantPast
            if kind=="session_meta" {
                cwd=p["cwd"] as? String
                if let source=p["source"] as? [String:Any],let sub=source["subagent"] as? [String:Any] {
                    category=(sub["other"] as? String)=="guardian" ? "service":"agent"
                }
                continue
            }
            if kind=="event_msg",type=="task_started",let id=p["turn_id"] as? String {
                active=id;if dates[id]==nil {order.append(id);dates[id]=date};continue
            }
            guard let turn=active else{continue}
            defer {if kind=="event_msg" && ["task_complete","turn_aborted"].contains(type ?? "") {active=nil}}
            // Guardian prompts contain internal agent history, not a user conversation.
            guard category != "service" else{continue}
            var role:String?,text="",phase=p["phase"] as? String,isCanonical=false
            if kind=="response_item",type=="message" {
                role=p["role"] as? String
                guard role=="user" || role=="assistant" else{continue}
                guard role != "assistant" || phase==nil || ["commentary","final_answer","final"].contains(phase!) else{continue}
                text=(p["content"] as? [[String:Any]] ?? []).compactMap { item in
                    switch item["type"] as? String {
                    case "input_text","output_text","text":return item["text"] as? String
                    case "input_image","image":return "[Изображение]"
                    case "input_audio","audio":return "[Аудио]"
                    default:return nil
                    }
                }.joined(separator:"\n")
                isCanonical=true
            } else if (kind=="event_msg" || kind=="response_item") && ["user_message","agent_message"].contains(type ?? "") {
                role=type=="user_message" ? "user":"assistant";text=p["message"] as? String ?? ""
                guard role != "assistant" || phase==nil || ["commentary","final_answer","final"].contains(phase!) else{continue}
            } else if kind=="event_msg",type=="task_complete" {
                role="assistant";phase="final_answer";text=p["last_agent_message"] as? String ?? ""
            }
            guard let role else{continue}
            if role=="user" {text=userText(text)}
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{continue}
            let message=TranscriptMessage(id:"\(turn):\(index)",role:role,text:text,date:date,phase:phase)
            if isCanonical {canonical[turn,default:[]].append(message)} else {fallback[turn,default:[]].append(message)}
        }
        let turns=order.map { id -> TranscriptTurn in
            var messages=canonical[id] ?? []
            // Prefer the canonical stream per role. Never show the same reply twice
            // via response_item, agent_message and task_complete.
            for role in ["user","assistant"] {
                if role=="user" && messages.contains(where:{$0.role==role}) {continue}
                var seen=Set(messages.filter{$0.role==role}.map{$0.text.trimmingCharacters(in:.whitespacesAndNewlines)})
                for m in fallback[id] ?? [] where m.role==role {
                    if seen.insert(m.text.trimmingCharacters(in:.whitespacesAndNewlines)).inserted {messages.append(m)}
                }
            }
            messages.sort { $0.date == $1.date ? (Int($0.id.split(separator:":").last ?? "0") ?? 0)<(Int($1.id.split(separator:":").last ?? "0") ?? 0):$0.date<$1.date }
            return TranscriptTurn(id:id,messages:messages,date:dates[id] ?? .distantPast)
        }
        return TranscriptDocument(turns:turns,workingDirectory:cwd,category:category)
    }
}

/// Full messages stay in memory; the database stores only previews and source paths.
public actor TranscriptRepository {
    public static let shared=TranscriptRepository()
    public init() {}
    private struct Entry {var fingerprint:String;var document:TranscriptDocument}
    private var cache:[String:Entry]=[:]
    public func read(path:String) throws -> TranscriptDocument {
        let url=URL(fileURLWithPath:path),values=try url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
        let key="\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let entry=cache[path],entry.fingerprint==key {return entry.document}
        try Task.checkCancellation()
        let document=Transcript.parse(try Data(contentsOf:url,options:.mappedIfSafe))
        try Task.checkCancellation()
        if cache.count>=12 {cache.removeAll()}
        cache[path]=Entry(fingerprint:key,document:document)
        return document
    }
    public func search(_ query:String,runs:[RunRecord]) async throws -> (matches:Set<String>,unavailable:Int) {
        var matches=Set<String>(),unavailable=0
        let byPath=Dictionary(grouping:runs.filter{!$0.isService && $0.sourcePath != nil},by:{$0.sourcePath!})
        for (path,group) in byPath {
            await Task.yield()
            try Task.checkCancellation()
            do {
                let ids=Set(group.map(\.id)),document=try read(path:path)
                for turn in document.turns where ids.contains(turn.id) && turn.messages.contains(where:{$0.text.localizedCaseInsensitiveContains(query)}) {matches.insert(turn.id)}
            } catch is CancellationError {throw CancellationError()}
            catch {unavailable += group.count}
        }
        return (matches,unavailable)
    }
}
