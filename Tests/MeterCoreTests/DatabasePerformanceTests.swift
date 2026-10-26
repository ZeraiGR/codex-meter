import Foundation
import MeterCore

extension MeterCoreTests {
    func testOpeningReaderDoesNotWaitForWriter() throws {
        let writer=try database()
        defer {try? FileManager.default.removeItem(at:writer.directory)}
        try writer.set("committed","before")
        try writer.transaction {
            try writer.set("committed","after")
            let reader=try Database(directory:writer.directory)
            XCTAssertEqual(try reader.value("committed"),"before")
        }
        XCTAssertEqual(try Database(directory:writer.directory).value("committed"),"after")
    }

    func testAttributionSweepKeepsBoundariesAndUnorderedInput() throws {
        let reset=epoch.addingTimeInterval(604800).timeIntervalSince1970
        func observation(_ seconds:Double,_ percent:Double)->QuotaObservation {
            QuotaObservation(account:"account",date:epoch.addingTimeInterval(seconds),window:.init(usedPercent:percent,windowDurationMins:10080,resetsAt:reset))
        }
        func run(_ id:String,_ start:Double,_ end:Double?,_ event:Double)->RunRecord {
            RunRecord(id:id,thread:id,started:epoch.addingTimeInterval(start),ended:end.map{epoch.addingTimeInterval($0)},tokens:.init(input:100),taskID:id,tokenEvents:[TokenEvent(date:epoch.addingTimeInterval(event),tokens:.init(input:100))])
        }
        let runs=[run("late",120,nil,180),run("old",-200,-100,-150),run("early",0,60,60),run("middle",60,120,120)]
        let observations=[observation(0,0),observation(60,10),observation(120,20),observation(180,30)]
        let result=Attribution.compute(runs:runs,observations:observations,payments:[])
        for id in ["early","middle","late"] {XCTAssertEqual(try XCTUnwrap(result[id]?.points),10,accuracy:0.0001)}
        XCTAssertNil(result["old"])
        // A backwards jump must reset the sweep, matching the original interval semantics.
        let reordered=[observations[2],observations[3],observations[0],observations[1]]
        let back=Attribution.compute(runs:runs,observations:reordered,payments:[])
        XCTAssertEqual(try XCTUnwrap(back["early"]?.points),10,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(back["late"]?.points),10,accuracy:0.0001)
        XCTAssertNil(back["middle"])
    }

    func testCompactionTitlePreservesRequestsAndBackfillsHistory() throws {
        let db=try database()
        defer {try? FileManager.default.removeItem(at:db.directory)}
        let home=db.directory.appendingPathComponent("codex"),sessions=home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at:sessions,withIntermediateDirectories:true)
        var text=try transcriptLine("session_meta",["id":"thread","source":"cli"])
        text += try transcriptLine("event_msg",["type":"task_started","turn_id":"compact"])
        text += try transcriptLine("compacted",["message":"internal summary must not become a title"],1)
        text += try transcriptLine("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":100]]],2)
        text += try transcriptLine("event_msg",["type":"task_complete","turn_id":"compact"],3)
        text += try transcriptLine("event_msg",["type":"task_started","turn_id":"request"],4)
        text += try transcriptLine("response_item",message("user","Проверь интерфейс"),5)
        text += try transcriptLine("compacted",["message":"internal"],6)
        text += try transcriptLine("event_msg",["type":"task_complete","turn_id":"request"],7)
        text += try transcriptLine("event_msg",["type":"task_started","turn_id":"unknown"],8)
        let file=sessions.appendingPathComponent("test.jsonl")
        try Data(text.utf8).write(to:file)
        var runs=Journal.parse(Data(text.utf8),fallbackThread:"thread")
        XCTAssertEqual(runs[0].title,"Сжатие контекста Codex")
        XCTAssertEqual(runs[1].title,"Проверь интерфейс")
        XCTAssertEqual(runs[2].title,"Продолжение без нового запроса")
        let task=WorkTask(title:"История",kind:"");try db.saveTask(task)
        runs[0].title="Продолжение без нового запроса";runs[0].sourcePath=file.path
        try db.saveRun(runs[0]);try db.bind(thread:"thread",turn:"compact",task:task.id)
        let values=try file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
        try db.set("file:"+file.path,"execution-v1:\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        XCTAssertEqual(try Journal.sync(db:db,home:home),1)
        let restored=try XCTUnwrap(db.runs().first{$0.id=="compact"})
        XCTAssertEqual(restored.title,"Сжатие контекста Codex");XCTAssertEqual(restored.tokens.total,100)
        XCTAssertEqual(restored.taskID,task.id);XCTAssertEqual(try db.task(task.id)?.status,task.status)
        XCTAssertEqual(try Journal.sync(db:db,home:home),0)
    }
}
