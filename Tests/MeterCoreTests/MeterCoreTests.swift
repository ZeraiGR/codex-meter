import Foundation
import MeterCore

final class MeterCoreTests {
    let day:Double=86400
    let epoch=Date(timeIntervalSince1970:1_780_000_000)
    func database() throws -> Database {try Database(directory:FileManager.default.temporaryDirectory.appendingPathComponent("meter-test-"+UUID().uuidString))}
    func testPriceFromActualPayment() {
        let bill=Payment(amount:6000,start:epoch,end:epoch.addingTimeInterval(28*day))
        XCTAssertEqual(bill.cost(points:10,windowSeconds:7*day),150,accuracy:0.0001)
        XCTAssertEqual(bill.cost(points:20,windowSeconds:7*day),300,accuracy:0.0001)
        XCTAssertEqual(4*bill.cost(points:10,windowSeconds:7*day)+2*bill.cost(points:20,windowSeconds:7*day),1200)
    }
    func testAvailableSeparatesFutureResets() throws {
        let bill=Payment(amount:6000,start:epoch,end:epoch.addingTimeInterval(28*day))
        let window=QuotaWindow(usedPercent:10,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(7*day).timeIntervalSince1970)
        let value=try XCTUnwrap(bill.available(window:window,now:epoch.addingTimeInterval(day)))
        XCTAssertEqual(value.current,1350);XCTAssertEqual(value.future,4500)
        XCTAssertNil(bill.available(window:window,now:epoch.addingTimeInterval(8*day)))
    }
    func testPaymentOverlapAndMissingPeriod() throws {
        let db=try database()
        try db.savePayment(.init(amount:6000,start:epoch,end:epoch.addingTimeInterval(28*day)))
        XCTAssertThrowsError(try db.savePayment(.init(amount:100,start:epoch.addingTimeInterval(day),end:epoch.addingTimeInterval(2*day))))
        try db.savePayment(.init(amount:7000,start:epoch.addingTimeInterval(28*day),end:epoch.addingTimeInterval(56*day)))
        XCTAssertEqual(try db.payments().count,2)
        XCTAssertThrowsError(try db.savePayment(.init(amount:Double.nan,start:epoch,end:epoch.addingTimeInterval(day))))
    }
    func testPartialBillingWindowDoesNotExceedPayment() throws {
        let bill=Payment(amount:100,start:epoch,end:epoch.addingTimeInterval(day))
        let window=QuotaWindow(usedPercent:0,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(3*day).timeIntervalSince1970)
        let value=try XCTUnwrap(bill.available(window:window,now:epoch))
        XCTAssertEqual(value.current+value.future,100)
    }
    func testCachedAndReasoningNotDoubleCounted() {
        let value=TokenCount(input:100,cached:80,output:20,reasoning:10)
        XCTAssertEqual(value.total,120)
        XCTAssertEqual(value.delta(from:value).total,0)
        XCTAssertEqual(TokenCount(input:10,output:2).delta(from:value).total,12)
    }
    func testParallelTimeIsUnion() {
        let value=TaskSummary.unionSeconds([(epoch,epoch.addingTimeInterval(100)),(epoch.addingTimeInterval(20),epoch.addingTimeInterval(80)),(epoch.addingTimeInterval(90),epoch.addingTimeInterval(150)),(epoch.addingTimeInterval(200),epoch.addingTimeInterval(210))])
        XCTAssertEqual(value,160)
    }
    func testFullTimeIncludesPauseBeforeTaskCompletion() {
        let task=WorkTask(title:"Ревью API",kind:"code-review",status:"completed",created:epoch,finished:epoch.addingTimeInterval(180))
        let run=RunRecord(id:"a",thread:"t",started:epoch,ended:epoch.addingTimeInterval(60))
        let summary=TaskSummary(task:task,runs:[run],quotaPoints:nil,rubles:nil,quotaQuality:"unknown")
        XCTAssertEqual(summary.activeSeconds,60);XCTAssertEqual(summary.wallSeconds,180)
    }
    func testJournalDeduplicatesCountersAndIgnoresPartialLine() throws {
        func line(_ type:String,_ payload:[String:Any],_ second:Int) throws -> String {
            let date=ISO8601DateFormatter().string(from:epoch.addingTimeInterval(Double(second)))
            return String(decoding:try JSONSerialization.data(withJSONObject:["type":type,"timestamp":date,"payload":payload]),as:UTF8.self)+"\n"
        }
        var data=try line("session_meta",["id":"thread"],0)
        data += try line("event_msg",["type":"task_started","turn_id":"one"],0)
        let tokens:[String:Any]=["type":"token_count","info":["total_token_usage":["input_tokens":100,"cached_input_tokens":80,"output_tokens":20,"reasoning_output_tokens":10]]]
        data += try line("event_msg",tokens,1);data += try line("event_msg",tokens,2)
        data += try line("event_msg",["type":"task_complete","turn_id":"one"],3)
        data += try line("event_msg",["type":"task_started","turn_id":"two"],4)
        data += try line("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":150,"output_tokens":30]]],5)
        data += "{\"incomplete\":"
        let runs=Journal.parse(Data(data.utf8),fallbackThread:"fallback")
        XCTAssertEqual(runs.count,2);XCTAssertEqual(runs[0].tokens.total,120);XCTAssertEqual(runs[1].tokens.total,60)
        XCTAssertEqual(runs[0].tokenEvents.count,1);XCTAssertEqual(runs[0].ended,epoch.addingTimeInterval(3))
        let db=try database();for _ in 0..<2 {for run in runs {try db.saveRun(run)}}
        XCTAssertEqual(try db.runs().reduce(0){$0+$1.tokens.total},180)
    }
    func testTaskSpansTurnsAndEndDoesNotLoseFinalTokens() throws {
        let db=try database(),task=WorkTask(title:"Ревью API",kind:"code-review")
        try db.saveTask(task);try db.bind(thread:"t",turn:"a",task:task.id);try db.bind(thread:"t",turn:"b",task:task.id)
        try db.saveRun(.init(id:"a",thread:"t",started:epoch,tokens:.init(input:100)))
        var complete=task;complete.status="completed";try db.saveTask(complete)
        try db.saveRun(.init(id:"b",thread:"t",started:epoch.addingTimeInterval(20),tokens:.init(input:200)))
        XCTAssertEqual(try db.summaries().first?.tokens.total,300)
    }
    func testMergeAndUnassignedResources() throws {
        let db=try database(),a=WorkTask(title:"A",kind:"code-review"),b=WorkTask(title:"B",kind:"code-review")
        try db.saveTask(a);try db.saveTask(b)
        try db.bind(thread:"t",turn:"a",task:a.id);try db.bind(thread:"t",turn:"b",task:b.id)
        try db.saveRun(.init(id:"a",thread:"t",started:epoch,tokens:.init(input:10)))
        try db.saveRun(.init(id:"b",thread:"t",started:epoch,tokens:.init(input:20)))
        try db.saveRun(.init(id:"c",thread:"t",started:epoch,tokens:.init(input:90)))
        try db.mergeTasks(source:a.id,target:b.id)
        XCTAssertEqual(try db.tasks().count,1);XCTAssertEqual(try db.summaries().first?.tokens.total,30)
        XCTAssertEqual(try db.runs().filter{$0.taskID==nil}.count,1)
    }
    func testWarningsAt50AndNoDuplicates() {
        let window=QuotaWindow(usedPercent:81,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(day).timeIntervalSince1970)
        XCTAssertEqual(AlertPolicy.pending(window:window,thresholds:AlertPolicy.defaults,sent:[],now:epoch),[50,80])
        XCTAssertEqual(AlertPolicy.pending(window:window,thresholds:AlertPolicy.defaults,sent:[50,80],now:epoch),[])
        var next=window;next.resetsAt! += 7*day
        XCTAssertNotEqual(AlertPolicy.key(account:"a",bucket:"codex",window:window),AlertPolicy.key(account:"a",bucket:"codex",window:next))
        XCTAssertEqual(AlertPolicy.pending(window:window,thresholds:AlertPolicy.defaults,sent:[],now:epoch.addingTimeInterval(2*day)),[])
    }
    func testExpiryReminderAt35PercentTwoDaysAndOneDay() {
        var w=QuotaWindow(usedPercent:65,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(2*day).timeIntervalSince1970)
        XCTAssertTrue(AlertPolicy.expiring(window:w,days:2,minimumRemaining:35,now:epoch))
        XCTAssertFalse(AlertPolicy.expiring(window:w,days:1,minimumRemaining:35,now:epoch))
        XCTAssertTrue(AlertPolicy.expiring(window:w,days:1,minimumRemaining:35,now:epoch.addingTimeInterval(day)))
        w.usedPercent=66
        XCTAssertFalse(AlertPolicy.expiring(window:w,days:1,minimumRemaining:35,now:epoch.addingTimeInterval(day)))
        w.usedPercent=0
        XCTAssertFalse(AlertPolicy.expiring(window:w,days:1,minimumRemaining:35,now:epoch.addingTimeInterval(3*day)))
    }
    func testResetTimestampJitterPreservesNotificationIdentity() throws {
        let db=try database()
        let a=QuotaWindow(usedPercent:65,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(day).timeIntervalSince1970)
        var b=a;b.resetsAt! -= 1
        XCTAssertTrue(AlertPolicy.sameWindow(a,b))
        let first=try db.alertKey(account:"a",bucket:"codex",window:a)
        XCTAssertEqual(first,try db.alertKey(account:"a",bucket:"codex",window:b))
        b.resetsAt! += 7*day
        XCTAssertFalse(AlertPolicy.sameWindow(a,b))
        XCTAssertNotEqual(first,try db.alertKey(account:"a",bucket:"codex",window:b))
    }
    func testAttributionDoesNotAddDifferentWindowsOrCrossReset() {
        let event=TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100))
        let run=RunRecord(id:"a",thread:"t",started:epoch,ended:epoch.addingTimeInterval(50),tokens:event.tokens,taskID:"task",tokenEvents:[event])
        let a=QuotaObservation(account:"account",date:epoch,window:.init(usedPercent:10,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(7*day).timeIntervalSince1970))
        var b=a;b.date=epoch.addingTimeInterval(60);b.window.usedPercent=12
        let bill=Payment(amount:6000,start:epoch,end:epoch.addingTimeInterval(28*day))
        let result=Attribution.compute(runs:[run],observations:[a,b],payments:[bill])["task"]
        XCTAssertEqual(result?.points,2);XCTAssertEqual(result?.rubles,30)
        b.window.resetsAt! += 7*day
        XCTAssertNil(Attribution.compute(runs:[run],observations:[a,b],payments:[bill])["task"])
    }
    func testAttributionReservesUnassignedShare() throws {
        let e=TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100))
        let runs=[RunRecord(id:"a",thread:"t",started:epoch,ended:epoch.addingTimeInterval(50),tokens:e.tokens,taskID:"task",tokenEvents:[e]),RunRecord(id:"b",thread:"u",started:epoch,ended:epoch.addingTimeInterval(50),tokens:e.tokens,tokenEvents:[e])]
        let a=QuotaObservation(account:"a",date:epoch,window:.init(usedPercent:10,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(7*day).timeIntervalSince1970))
        var b=a;b.date=epoch.addingTimeInterval(60);b.window.usedPercent=12
        let value=try XCTUnwrap(Attribution.compute(runs:runs,observations:[a,b],payments:[])["task"])
        XCTAssertEqual(value.points,1);XCTAssertNil(value.rubles);XCTAssertTrue(value.quality.hasPrefix("Грубая"))
    }
    func testAttributionMissingSnapshotsDoesNotPretendTotal() {
        let e=TokenEvent(date:epoch.addingTimeInterval(300),tokens:.init(input:100))
        let r=RunRecord(id:"a",thread:"t",started:epoch,tokens:.init(input:200),taskID:"task",tokenEvents:[e])
        let a=QuotaObservation(account:"a",date:epoch,window:.init(usedPercent:10,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(7*day).timeIntervalSince1970))
        var b=a;b.date=epoch.addingTimeInterval(400);b.window.usedPercent=15
        XCTAssertNil(Attribution.compute(runs:[r],observations:[a,b],payments:[])["task"])
    }
    func testForecastRefusesUnfoundedConfidence() {
        let forecast=Predictor.estimate(kind:"code-review",history:[],snapshot:nil,payment:nil,now:epoch)
        XCTAssertEqual(forecast.risk,"unknown");XCTAssertNil(forecast.tokenMedian)
        let task=WorkTask(title:"Ревью API",kind:"code-review",status:"completed")
        let run=RunRecord(id:"turn",thread:"t",started:epoch,ended:epoch.addingTimeInterval(60),tokens:.init(input:100),model:"m")
        let s=TaskSummary(task:task,runs:[run],quotaPoints:20,rubles:10,quotaQuality:"Оценка")
        let snap=AccountSnapshot(accountKey:"a",fetchedAt:epoch,buckets:[.init(primary:.init(usedPercent:80,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(day).timeIntervalSince1970))])
        let high=Predictor.estimate(kind:"code-review",history:[s,s,s],snapshot:snap,payment:nil,model:"m",now:epoch)
        XCTAssertEqual(high.risk,"high");XCTAssertEqual(high.quotaUpper,24)
        XCTAssertEqual(Predictor.estimate(kind:"code-review",history:[s,s,s],snapshot:snap,payment:nil,model:"other",now:epoch).samples,0)
        XCTAssertEqual(Predictor.estimate(kind:"code-review",history:[s,s,s],snapshot:snap,payment:nil,now:epoch.addingTimeInterval(500)).risk,"unknown")
    }
    func testTaskCLIReusesAndPausesCorrectly() throws {
        let db=try database(),dir=db.directory
        let args=["task-start","--thread","t","--turn","one","--title","Ревью API 1","--kind","code-review"]
        let first=try Codec.decode(WorkTask.self,Commands.run(args,directory:dir))
        let second=try Codec.decode(WorkTask.self,Commands.run(args,directory:dir))
        XCTAssertEqual(first.id,second.id)
        _=try Commands.run(["task-start","--thread","t","--turn","two","--title","Ревью API 2","--kind","code-review"],directory:dir)
        XCTAssertEqual(try db.task(first.id)?.status,"paused")
        _=try Commands.run(["task-resume","--id",first.id,"--thread","u","--turn","three"],directory:dir)
        XCTAssertEqual(try db.activeTask(thread:"u")?.id,first.id)
        _=try Commands.run(["task-end","--id",first.id],directory:dir)
        XCTAssertNil(try db.activeTask(thread:"u"))
    }
    func testHookProvidesTaskContextWithoutNetwork() throws {
        let db=try database()
        let payload=Data("{\"session_id\":\"thread\",\"turn_id\":\"turn\"}".utf8)
        let response=try Commands.run(["hook"],directory:db.directory,input:payload)
        let object=try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any]
        XCTAssertNotNil(object?["hookSpecificOutput"])
        XCTAssertTrue(response.contains("task-start"))
        XCTAssertTrue(try db.tasks().isEmpty)
    }
}
