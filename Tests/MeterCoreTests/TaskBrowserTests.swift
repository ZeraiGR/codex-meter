import Foundation
import MeterCore

extension MeterCoreTests {
    private func browserTask(_ id:String,tokens:Int64,seconds:Double,cost:Double?,status:String="paused",kind:String="Разработка")->TaskSummary {
        let task=WorkTask(id:id,title:id,kind:kind,status:status,created:epoch)
        let run=RunRecord(id:id,thread:id,started:epoch,ended:epoch.addingTimeInterval(seconds),tokens:.init(input:tokens),taskID:id)
        return TaskSummary(task:task,runs:[run],quotaPoints:nil,rubles:cost,quotaQuality:"")
    }
    func testTaskSortingUsesNumbersAndKeepsUnknownCostsLast() {
        let tasks=[browserTask("A",tokens:900,seconds:60,cost:nil),browserTask("B",tokens:10000,seconds:20,cost:100),browserTask("C",tokens:2000,seconds:120,cost:9)]
        XCTAssertEqual(TaskListQuery.apply(tasks,sort:.tokens).map(\.id),["B","C","A"])
        XCTAssertEqual(TaskListQuery.apply(tasks,sort:.time).map(\.id),["C","A","B"])
        XCTAssertEqual(TaskListQuery.apply(tasks,sort:.cost).map(\.id),["B","C","A"])
        XCTAssertEqual(TaskListQuery.apply(tasks,sort:.cost,ascending:true).map(\.id),["C","B","A"])
        XCTAssertEqual(TaskListQuery.apply(tasks,sort:.title,ascending:true).map(\.id),["A","B","C"])
    }
    func testTaskFiltersCombineStatusKindAndWordsWithoutLosingSelectionIdentity() {
        let tasks=[browserTask("API заказов",tokens:1,seconds:1,cost:nil,status:"completed",kind:"Code Review"),browserTask("API клиентов",tokens:2,seconds:2,cost:nil,status:"paused",kind:"Code Review"),browserTask("Релиз",tokens:3,seconds:3,cost:nil,status:"completed",kind:"Разработка")]
        XCTAssertEqual(TaskListQuery.apply(tasks,query:"review API",status:"completed",kind:"code").map(\.id),["API заказов"])
        XCTAssertEqual(TaskListQuery.apply(tasks,kind:"несуществующий").count,0)
        XCTAssertEqual(Set(TaskListQuery.apply(tasks,sort:.tokens,ascending:true).map(\.id)),Set(tasks.map(\.id)))
    }
    func testTaskSortingUsesSummedMeasuredCostAndStableTies() {
        var a=browserTask("A",tokens:100,seconds:10,cost:nil)
        let b=browserTask("B",tokens:100,seconds:10,cost:10)
        a.measuredRubles=20;a.costCoverage=0.5
        a.weeklyQuota=WeeklyQuotaUsage(points:3,coverage:0.5,windowCount:1)
        XCTAssertEqual(TaskListQuery.apply([b,a],sort:.cost).map(\.id),["A","B"])
        XCTAssertEqual(TaskListQuery.apply([b,a],sort:.quota,ascending:true).map(\.id),["A","B"])
        XCTAssertEqual(TaskListQuery.apply([b,a],sort:.tokens).map(\.id),["A","B"])
    }
    private func weeklyPair(at date:Date,reset:Date,used:Double=2,account:String="one",minutes:Int=10080)->[QuotaObservation] {
        [QuotaObservation(account:account,date:date,window:QuotaWindow(usedPercent:0,windowDurationMins:minutes,resetsAt:reset.timeIntervalSince1970)),QuotaObservation(account:account,date:date.addingTimeInterval(60),window:QuotaWindow(usedPercent:used,windowDurationMins:minutes,resetsAt:reset.timeIntervalSince1970))]
    }
    func testWeeklyQuotaDoesNotDependOnPaymentAndMarksPartialCoverage() throws {
        let run=RunRecord(id:"r",thread:"r",started:epoch,ended:epoch.addingTimeInterval(60),tokens:.init(input:200),taskID:"task",tokenEvents:[TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100))])
        let obs=weeklyPair(at:epoch,reset:epoch.addingTimeInterval(7*day))
        let result=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs,payments:[])["task"])
        let quota=try XCTUnwrap(result.weeklyQuota)
        XCTAssertEqual(quota.points,2);XCTAssertEqual(quota.coverage,0.5);XCTAssertEqual(quota.windowCount,1)
        XCTAssertFalse(quota.complete);XCTAssertNil(result.points);XCTAssertNil(result.measuredRubles)
    }
    func testWeeklyQuotaSumsAcrossResetsWithoutCappingAt100() throws {
        let next=epoch.addingTimeInterval(7*day)
        let obs=weeklyPair(at:epoch,reset:next,used:70)+weeklyPair(at:next,reset:next.addingTimeInterval(7*day),used:80)
        let runs=[epoch,next].enumerated().map { index,date in
            RunRecord(id:"r\(index)",thread:"t",started:date,ended:date.addingTimeInterval(60),tokens:.init(input:100),taskID:"task",tokenEvents:[TokenEvent(date:date.addingTimeInterval(30),tokens:.init(input:100))])
        }
        let result=try XCTUnwrap(Attribution.compute(runs:runs,observations:obs,payments:[])["task"]?.weeklyQuota)
        XCTAssertEqual(result.points,150);XCTAssertEqual(result.windowCount,2);XCTAssertTrue(result.complete)
    }
    func testWeeklyQuotaRejectsShortWindowsAndMixedAccounts() {
        var run=RunRecord(id:"r",thread:"t",started:epoch,ended:epoch.addingTimeInterval(400),tokens:.init(input:200),taskID:"task",tokenEvents:[TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100)),TokenEvent(date:epoch.addingTimeInterval(330),tokens:.init(input:100))])
        let reset=epoch.addingTimeInterval(7*day)
        let a=weeklyPair(at:epoch,reset:reset)
        let b=weeklyPair(at:epoch.addingTimeInterval(300),reset:reset,account:"two")
        XCTAssertNil(Attribution.compute(runs:[run],observations:a+b,payments:[])["task"]?.weeklyQuota)
        run.tokens = .init(input:100)
        XCTAssertNil(Attribution.compute(runs:[run],observations:weeklyPair(at:epoch,reset:reset,minutes:300),payments:[])["task"]?.weeklyQuota)
        XCTAssertNil(Attribution.compute(runs:[run],observations:weeklyPair(at:epoch,reset:reset,used:0),payments:[])["task"]?.weeklyQuota)
    }
    func testWeeklyQuotaSurvivesDatabaseAndCLIWithoutChangingFullQuotaContract() throws {
        let db=try database(),run=RunRecord(id:"r",thread:"t",started:epoch,ended:epoch.addingTimeInterval(60),tokens:.init(input:200),taskID:"task",tokenEvents:[TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100))])
        try db.saveTask(WorkTask(id:"task",title:"Разработка",kind:"Разработка"));try db.saveRun(run)
        for obs in weeklyPair(at:epoch,reset:epoch.addingTimeInterval(7*day)) {try db.saveSnapshot(AccountSnapshot(accountKey:obs.account,fetchedAt:obs.date,buckets:[QuotaBucket(primary:obs.window)]))}
        let summary=try XCTUnwrap(try db.summaries().first)
        XCTAssertEqual(summary.weeklyQuota?.points,2);XCTAssertEqual(summary.weeklyQuota?.coverage,0.5);XCTAssertNil(summary.quotaPoints)
        let json=try Commands.run(["tasks"],directory:db.directory)
        let rows=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [[String:Any]])
        let weekly=try XCTUnwrap(rows.first?["weeklyQuota"] as? [String:Any])
        XCTAssertEqual(weekly["points"] as? Double,2);XCTAssertEqual(weekly["coverage"] as? Double,0.5)
        XCTAssertTrue(rows.first?["quotaPoints"] is NSNull)
    }
}
