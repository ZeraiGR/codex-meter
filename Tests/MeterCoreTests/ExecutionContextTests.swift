import Foundation
import MeterCore

extension MeterCoreTests {
    func testLegacyContextBeforeTurnKeepsItsRecordedModel() throws {
        let data=Data(("""
        {"timestamp":"2026-10-25T10:00:00Z","type":"turn_context","payload":{"model":"legacy-model","effort":"high"}}
        {"timestamp":"2026-10-25T10:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"legacy"}}
        {"timestamp":"2026-10-25T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10}}}}
        """+"\n").utf8)
        let run=try XCTUnwrap(Journal.parse(data,fallbackThread:"thread").first)
        XCTAssertEqual(run.model,"legacy-model");XCTAssertEqual(run.effort,"high")
        XCTAssertEqual(run.execution?.configurations.first?.model,"legacy-model")
        XCTAssertEqual(run.execution?.configurations.first?.tokens.total,10)
    }
    func testExecutionContextTracksChangesAndCompletedToolsWithoutSecrets() throws {
        func row(_ type:String,_ payload:[String:Any])->String {
            String(data:try! JSONSerialization.data(withJSONObject:["timestamp":"2026-10-25T10:00:00Z","type":type,"payload":payload]),encoding:.utf8)!+"\n"
        }
        var log=row("session_meta",["id":"thread","originator":"codex-tui","cli_version":"0.test","source":"cli","model_provider":"openai"])
        log+=row("event_msg",["type":"thread_settings_applied","thread_settings":["service_tier":"priority"]])
        log+=row("event_msg",["type":"task_started","turn_id":"one","model_context_window":200000])
        log+=row("turn_context",["turn_id":"one","model":"model-a-2026-01-01","effort":"high"])
        log+=row("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":100,"output_tokens":20]]])
        log+=row("turn_context",["turn_id":"one","model":"model-b","effort":"low"])
        log+=row("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":150,"output_tokens":30]]])
        let call:[String:Any]=["type":"item_completed","turn_id":"one","item":["type":"McpToolCall","id":"call","server":"docs","tool":"search","status":"completed","arguments":["token":"DO_NOT_STORE"],"result":"PRIVATE_RESULT"]]
        log+=row("event_msg",call);log+=row("event_msg",call)
        log+=row("event_msg",["type":"item_completed","turn_id":"one","item":["type":"McpToolCall","id":"failed-call","server":"docs","tool":"fetch","status":"completed","duration":["secs":1,"nanos":500000000],"result":["isError":true]]])
        log+=row("event_msg",["type":"task_complete","turn_id":"one"])
        log+=row("event_msg",["type":"task_started","turn_id":"two"])
        log+=row("turn_context",["turn_id":"two","model":"model-c","effort":"medium"])
        log+=row("event_msg",["type":"task_complete","turn_id":"two"])
        log+=row("event_msg",["type":"task_started","turn_id":"missing-context"])
        log+=row("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":160,"output_tokens":30]]])
        let runs=Journal.parse(Data(log.utf8),fallbackThread:"fallback")
        let run=try XCTUnwrap(runs.first{$0.id=="one"}),context=try XCTUnwrap(run.execution)
        XCTAssertEqual(context.harness,"codex-tui 0.test");XCTAssertEqual(context.source,"cli")
        XCTAssertEqual(context.configurations.map(\.model),["model-a-2026-01-01","model-b"])
        XCTAssertEqual(context.configurations.map(\.effort),["high","low"])
        XCTAssertEqual(context.configurations.map{$0.tokens.total},[120,60])
        XCTAssertEqual(context.configurations.first?.serviceTier,"priority")
        XCTAssertEqual(context.configurations.first?.contextWindow,200000)
        XCTAssertEqual(context.calls.count,2);XCTAssertEqual(context.calls.first?.server,"docs")
        XCTAssertEqual(context.calls.last?.status,"failed");XCTAssertEqual(context.calls.last?.duration,1.5)
        XCTAssertTrue(runs.first{$0.id=="two"}?.execution?.calls.isEmpty == true)
        XCTAssertEqual(runs.first{$0.id=="missing-context"}?.model,"")
        XCTAssertEqual(runs.first{$0.id=="missing-context"}?.effort,"")
        let encoded=try Codec.encode(run)
        XCTAssertFalse(encoded.contains("DO_NOT_STORE"));XCTAssertFalse(encoded.contains("PRIVATE_RESULT"))
        let db=try database();defer{try? FileManager.default.removeItem(at:db.directory)}
        try db.saveRun(run);XCTAssertEqual(try db.runs().first?.execution?.calls.count,2)
    }
    func testExecutionContextBackfillsOldRunsWithoutChangingBindings() throws {
        let db=try database();defer{try? FileManager.default.removeItem(at:db.directory)}
        let root=db.directory.appendingPathComponent("codex"),sessions=root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at:sessions,withIntermediateDirectories:true)
        let path=sessions.appendingPathComponent("history.jsonl")
        let log="""
        {"timestamp":"2026-10-25T10:00:00Z","type":"session_meta","payload":{"id":"thread","originator":"codex-tui","cli_version":"0.test"}}
        {"timestamp":"2026-10-25T10:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"one"}}
        {"timestamp":"2026-10-25T10:00:02Z","type":"turn_context","payload":{"turn_id":"one","model":"test-model","effort":"high"}}
        {"timestamp":"2026-10-25T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20}}}}
        {"timestamp":"2026-10-25T10:00:04Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"one"}}
        """+"\n"
        try log.write(to:path,atomically:true,encoding:.utf8)
        var old=Journal.parse(Data(log.utf8),fallbackThread:"thread")[0];old.execution=nil
        let json=try Codec.encode(old);XCTAssertNil(try Codec.decode(RunRecord.self,json).execution)
        try db.saveTask(WorkTask(id:"task",title:"Task",kind:"test"));try db.saveRun(old);try db.bind(thread:"thread",turn:"one",task:"task")
        let values=try path.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        try db.set("file:"+path.path,"transcript-v2:\(values.fileSize!):\(values.contentModificationDate!.timeIntervalSince1970)")
        XCTAssertEqual(try Journal.sync(db:db,home:root),1)
        let run=try XCTUnwrap(try db.runs().first)
        XCTAssertEqual(run.taskID,"task");XCTAssertEqual(run.tokens.total,old.tokens.total)
        XCTAssertEqual(run.execution?.clientVersion,"0.test")
        XCTAssertEqual(try Journal.sync(db:db,home:root),0)
    }
}
