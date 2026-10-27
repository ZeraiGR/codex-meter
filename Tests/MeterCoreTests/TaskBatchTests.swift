import Foundation
import MeterCore

extension MeterCoreTests {
    func testBatchStatusPreservesTaskHistory() throws {
        let db=try database()
        defer {try? FileManager.default.removeItem(at:db.directory)}
        for id in ["a","b","c"] {try db.saveTask(WorkTask(id:id,title:id,kind:"review",created:epoch))}
        try db.saveRun(RunRecord(id:"run",thread:"thread",started:epoch,tokens:.init(input:123),taskID:"a"))
        try db.bind(thread:"thread",turn:"run",task:"a")
        try db.updateTaskStatuses(["a","b","a"],status:"completed")
        let finished=try XCTUnwrap(try db.task("a")?.finished)
        try db.updateTaskStatuses(["a"],status:"completed")
        XCTAssertEqual(try db.task("a")?.finished,finished)
        try db.updateTaskStatuses(["a","b"],status:"paused")
        XCTAssertNil(try db.task("a")?.finished)
        XCTAssertEqual(try db.task("a")?.created,epoch)
        XCTAssertEqual(try db.task("c")?.status,"active")
        XCTAssertEqual(try db.runs().first?.tokens.total,123)
        XCTAssertEqual(try db.runs().first?.taskID,"a")
        XCTAssertThrowsError(try db.updateTaskStatuses(["a","missing"],status:"failed"))
        XCTAssertEqual(try db.task("a")?.status,"paused")
        XCTAssertThrowsError(try db.updateTaskStatuses(["a"],status:"invalid"))
        try db.updateTaskStatuses(["a","b"],status:"ongoing")
        XCTAssertEqual(try db.task("a")?.status,"ongoing")
        XCTAssertNil(try db.task("a")?.finished)
        try db.saveRun(RunRecord(id:"next",thread:"thread",started:epoch,tokens:.init(input:10),taskID:"a"))
        XCTAssertEqual(try db.task("a")?.status,"ongoing")
        XCTAssertEqual(try db.summaries().first{$0.id=="a"}?.tokens.total,133)
    }

    func testBatchMergeIsAtomicAndPreservesBindingsAndTotals() throws {
        let db=try database()
        defer {try? FileManager.default.removeItem(at:db.directory)}
        for id in ["a","b","c","other"] {
            try db.saveTask(WorkTask(id:id,title:id,kind:"review",created:epoch))
            try db.saveRun(RunRecord(id:id,thread:id,started:epoch,tokens:.init(input:100),taskID:id))
            try db.bind(thread:id,turn:id,task:id)
            try db.set("active:"+id,id)
        }
        try db.exec("CREATE TRIGGER stop_merge BEFORE DELETE ON tasks WHEN OLD.id='b' BEGIN SELECT RAISE(ABORT,'simulated failure'); END")
        XCTAssertThrowsError(try db.mergeTasks(sources:["a","b"],target:"c"))
        XCTAssertEqual(try db.tasks().count,4)
        XCTAssertEqual(try db.runs().first{$0.id=="a"}?.taskID,"a")
        XCTAssertEqual(try db.activeTask(thread:"a")?.id,"a")
        try db.exec("DROP TRIGGER stop_merge")
        try db.mergeTasks(sources:["a","b","c","a"],target:"c")
        XCTAssertEqual(try db.tasks().count,2)
        XCTAssertEqual(try db.summaries().first{$0.id=="c"}?.tokens.total,300)
        XCTAssertEqual(try db.activeTask(thread:"a")?.id,"c")
        try db.saveRun(RunRecord(id:"a",thread:"a",started:epoch,tokens:.init(input:100)))
        XCTAssertEqual(try db.runs().first{$0.id=="a"}?.taskID,"c")
        XCTAssertEqual(try db.summaries().first{$0.id=="other"}?.tokens.total,100)
        XCTAssertThrowsError(try db.mergeTasks(sources:["c"],target:"c"))
    }
}
