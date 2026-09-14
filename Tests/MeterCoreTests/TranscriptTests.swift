import Foundation
import MeterCore

extension MeterCoreTests {
    func transcriptLine(_ kind:String,_ payload:[String:Any],_ offset:Int=0) throws -> String {
        let stamp=ISO8601DateFormatter().string(from:epoch.addingTimeInterval(Double(offset)))
        return String(decoding:try JSONSerialization.data(withJSONObject:["type":kind,"timestamp":stamp,"payload":payload]),as:UTF8.self)+"\n"
    }
    func message(_ role:String,_ text:String,_ phase:String?=nil) -> [String:Any] {
        var result:[String:Any]=["type":"message","role":role,"content":[["type":role=="user" ? "input_text":"output_text","text":text]]]
        if let phase {result["phase"]=phase};return result
    }
    func sampleTranscript() throws -> String {
        try transcriptLine("session_meta",["id":"thread","cwd":"/projects/orders-api","source":"cli"])
        + transcriptLine("event_msg",["type":"task_started","turn_id":"one"])
        + transcriptLine("response_item",message("user","<environment_context><cwd>/private</cwd></environment_context>"))
        + transcriptLine("response_item",message("user","<image name=\"schema\"></image>\nПроверь API заказов и обработку ошибок"),1)
        + transcriptLine("response_item",message("assistant","Проверю контракт API","commentary"),2)
        + transcriptLine("response_item",message("assistant","Основная проблема: пропущена валидация запроса","final_answer"),3)
        + transcriptLine("event_msg",["type":"task_complete","turn_id":"one","last_agent_message":"Основная проблема: пропущена валидация запроса"],4)
        + transcriptLine("event_msg",["type":"task_started","turn_id":"two"],5)
        + transcriptLine("response_item",message("user","Какие проверки добавить?"),6)
        + transcriptLine("response_item",message("assistant","Сначала валидация, затем интеграционные проверки","final_answer"),7)
        + transcriptLine("event_msg",["type":"task_complete","turn_id":"two"],8)
    }
    func testTranscriptCanonicalMessagesAndTurnBoundaries() throws {
        let data=Data(try sampleTranscript().utf8),document=Transcript.parse(data),runs=Journal.parse(data,fallbackThread:"x")
        XCTAssertEqual(document.turns.count,2)
        XCTAssertEqual(document.turns[0].messages.count,3)
        XCTAssertEqual(document.turns[1].messages.count,2)
        XCTAssertTrue(runs[0].title.contains("Проверь API"))
        XCTAssertFalse(runs[0].title.contains("environment_context"))
        XCTAssertEqual(runs[0].projectName,"orders-api")
        XCTAssertTrue(runs[0].preview?.contains("Основная проблема") == true)
    }
    func testTranscriptExcludesInternalRolesAndReasoning() throws {
        var text=try sampleTranscript()
        text += try transcriptLine("event_msg",["type":"task_started","turn_id":"three"],9)
        text += try transcriptLine("response_item",message("system","system-only"),10)
        text += try transcriptLine("response_item",message("developer","developer-only"),10)
        text += try transcriptLine("response_item",["type":"reasoning","text":"reasoning-only"],10)
        text += try transcriptLine("response_item",message("assistant","analysis-only","analysis"),10)
        text += try transcriptLine("response_item",["type":"function_call_output","output":"tool-only"],10)
        let messages=Transcript.parse(Data(text.utf8)).turns.flatMap(\.messages).map(\.text).joined()
        for forbidden in ["system-only","developer-only","reasoning-only","analysis-only","tool-only"] {XCTAssertFalse(messages.contains(forbidden))}
    }
    func testTranscriptLegacyAndDuplicateStreams() throws {
        var text=try transcriptLine("event_msg",["type":"task_started","turn_id":"one"])
        text += try transcriptLine("event_msg",["type":"user_message","message":"Старый формат"],1)
        text += try transcriptLine("event_msg",["type":"agent_message","message":"Готово","phase":"final_answer"],2)
        text += try transcriptLine("response_item",message("assistant","Готово","final_answer"),2)
        text += try transcriptLine("event_msg",["type":"task_complete","turn_id":"one","last_agent_message":"Готово"],3)
        text += "{\"partial\":"
        let messages=Transcript.parse(Data(text.utf8)).turns[0].messages
        XCTAssertEqual(messages.count,2);XCTAssertEqual(messages[0].text,"Старый формат");XCTAssertEqual(messages[1].text,"Готово")
    }
    func testServiceRunsKeepCountersWithoutInternalTranscript() throws {
        var text=try transcriptLine("session_meta",["id":"service","source":["subagent":["other":"guardian"]]])
        text += try transcriptLine("event_msg",["type":"task_started","turn_id":"one"])
        text += try transcriptLine("response_item",message("user","The following is the Codex agent history: internal data"),1)
        text += try transcriptLine("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":100,"output_tokens":10]]],2)
        let data=Data(text.utf8),run=try XCTUnwrap(Journal.parse(data,fallbackThread:"x").first)
        XCTAssertTrue(run.isService);XCTAssertEqual(run.tokens.total,110)
        XCTAssertEqual(Transcript.parse(data).turns.flatMap(\.messages).count,0)
        XCTAssertEqual(run.title,"Автоматическая проверка действия Codex")
    }
    func testOldRunRecordsDecodeWithoutTranscriptMetadata() throws {
        let run=RunRecord(id:"one",thread:"thread",started:epoch)
        var json=try JSONSerialization.jsonObject(with:Data(Codec.encode(run).utf8)) as! [String:Any]
        for key in ["sourcePath","workingDirectory","category","preview","messageCount"] {json.removeValue(forKey:key)}
        let decoded=try JSONDecoder().decode(RunRecord.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(decoded.sourcePath);XCTAssertFalse(decoded.isService)
    }
    func testTranscriptBackfillPreservesBindingsAndCounters() throws {
        let db=try database(),home=db.directory.appendingPathComponent("codex"),sessions=home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at:sessions,withIntermediateDirectories:true)
        let file=sessions.appendingPathComponent("test.jsonl")
        try Data(sampleTranscript().utf8).write(to:file)
        let task=WorkTask(title:"Ревью API",kind:"code-review");try db.saveTask(task)
        let old=RunRecord(id:"one",thread:"thread",started:epoch)
        try db.saveRun(old);try db.bind(thread:"thread",turn:"one",task:task.id)
        let values=try file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
        try db.set("file:"+file.path,"\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        XCTAssertEqual(try Journal.sync(db:db,home:home),1)
        let run=try XCTUnwrap(db.runs().first{$0.id=="one"})
        XCTAssertEqual(run.taskID,task.id)
        XCTAssertEqual(run.sourcePath.map{URL(fileURLWithPath:$0).resolvingSymlinksInPath().path},file.resolvingSymlinksInPath().path)
        XCTAssertTrue(run.title.contains("Проверь API"))
        XCTAssertEqual(try Journal.sync(db:db,home:home),0)
    }
    func testTranscriptSearchReadsAnswersAndInvalidatesCache() async throws {
        let db=try database(),file=db.directory.appendingPathComponent("test.jsonl")
        try Data(sampleTranscript().utf8).write(to:file)
        var run=RunRecord(id:"two",thread:"thread",started:epoch);run.sourcePath=file.path
        let repo=TranscriptRepository()
        let found=try await repo.search("валидация",runs:[run]);XCTAssertEqual(found.matches,Set(["two"]))
        let changed=try sampleTranscript().replacingOccurrences(of:"валидация",with:"совсем новое слово")
        try Data(changed.utf8).write(to:file)
        let updated=try await repo.search("совсем новое",runs:[run]);XCTAssertEqual(updated.matches,Set(["two"]))
        try FileManager.default.removeItem(at:file)
        let missing=try await repo.search("совсем новое",runs:[run]);XCTAssertEqual(missing.unavailable,1);XCTAssertTrue(missing.matches.isEmpty)
    }
}
