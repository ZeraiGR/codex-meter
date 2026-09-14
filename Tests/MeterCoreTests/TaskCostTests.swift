import Foundation
import MeterCore

extension MeterCoreTests {
    private func costFixture(total:Int64=200)->(RunRecord,[QuotaObservation],Payment) {
        let e=TokenEvent(date:epoch.addingTimeInterval(30),tokens:.init(input:100))
        let run=RunRecord(id:"cost",thread:"thread",started:epoch,ended:epoch.addingTimeInterval(120),tokens:.init(input:total),taskID:"task",tokenEvents:[e])
        let a=QuotaObservation(account:"account",date:epoch,window:.init(usedPercent:10,windowDurationMins:10080,resetsAt:epoch.addingTimeInterval(7*day).timeIntervalSince1970))
        var b=a;b.date=epoch.addingTimeInterval(60);b.window.usedPercent=12
        return (run,[a,b],Payment(amount:6000,start:epoch,end:epoch.addingTimeInterval(28*day)))
    }
    func testPartialCostIsPreservedWithoutPretendingToBeTotal() throws {
        let (run,obs,bill)=costFixture()
        let result=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs,payments:[bill])["task"])
        XCTAssertNil(result.rubles);XCTAssertNil(result.points)
        XCTAssertEqual(result.measuredRubles,30);XCTAssertEqual(result.costCoverage,0.5)
    }
    func testCostSumsAllRunsAndPreservesUnassignedShare() throws {
        let (run,obs,bill)=costFixture(total:100)
        var other=run;other.id="second"
        var unassigned=run;unassigned.id="outside";unassigned.taskID=nil
        let result=try XCTUnwrap(Attribution.compute(runs:[run,other,unassigned],observations:obs,payments:[bill])["task"])
        XCTAssertEqual(try XCTUnwrap(result.rubles),20,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(result.measuredRubles),20,accuracy:0.0001)
        XCTAssertEqual(result.costCoverage,1)
    }
    func testPartialPaymentDoesNotClaimFullCostCoverage() throws {
        let (run,obs,original)=costFixture(total:100)
        var bill=original;bill.start=epoch.addingTimeInterval(30);bill.end=bill.end.addingTimeInterval(30)
        let result=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs,payments:[bill])["task"])
        XCTAssertNil(result.rubles);XCTAssertEqual(result.measuredRubles,15);XCTAssertEqual(result.costCoverage,0.5)
        let unpaid=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs,payments:[])["task"])
        XCTAssertNil(unpaid.measuredRubles);XCTAssertNil(unpaid.rubles);XCTAssertEqual(unpaid.costCoverage,0)
    }
    func testZeroQuotaAndMixedAccountsDoNotProducePartialPrice() throws {
        var (run,obs,bill)=costFixture()
        obs[1].window.usedPercent=obs[0].window.usedPercent
        let zero=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs,payments:[bill])["task"])
        XCTAssertNil(zero.measuredRubles);XCTAssertNil(zero.rubles)
        obs[1].window.usedPercent=12
        var c=obs[0];c.account="other";c.date=epoch.addingTimeInterval(300)
        var d=c;d.date=epoch.addingTimeInterval(360);d.window.usedPercent=13
        run.ended=d.date;run.tokenEvents.append(TokenEvent(date:epoch.addingTimeInterval(330),tokens:.init(input:100)))
        let mixed=try XCTUnwrap(Attribution.compute(runs:[run],observations:obs+[c,d],payments:[bill])["task"])
        XCTAssertNil(mixed.measuredRubles);XCTAssertNil(mixed.rubles)
    }
    func testTaskSummaryKeepsMeasuredCostFromDatabase() throws {
        let (run,obs,bill)=costFixture();let db=try database()
        try db.saveTask(WorkTask(id:"task",title:"Проект",kind:"Разработка"));try db.saveRun(run);try db.bind(thread:run.thread,turn:run.id,task:"task");try db.savePayment(bill)
        for o in obs {try db.saveSnapshot(AccountSnapshot(accountKey:o.account,fetchedAt:o.date,buckets:[QuotaBucket(primary:o.window)]))}
        let summary=try XCTUnwrap(try db.summaries().first)
        XCTAssertNil(summary.rubles);XCTAssertEqual(summary.measuredRubles,30);XCTAssertEqual(summary.costCoverage,0.5)
    }
    func testProjectedTaskCostUsesUnroundedCoverageAndIncludesMeasuredPart() throws {
        var s=TaskSummary(task:WorkTask(title:"Проект",kind:"Разработка"),runs:[],quotaPoints:nil,rubles:nil,quotaQuality:"",measuredRubles:30,costCoverage:0.5)
        XCTAssertEqual(s.projectedRubles,60)
        XCTAssertNil(s.rubles);XCTAssertEqual(s.measuredRubles,30)
        s.measuredRubles=78.11088890867121;s.costCoverage=0.5396432148477152
        XCTAssertEqual(try XCTUnwrap(s.projectedRubles),144.74542949773536,accuracy:0.000001)
        s.rubles=140
        XCTAssertNil(s.projectedRubles)
    }
    func testProjectedTaskCostRejectsMissingAndInvalidInputs() {
        var s=TaskSummary(task:WorkTask(title:"Проект",kind:"Разработка"),runs:[],quotaPoints:nil,rubles:nil,quotaQuality:"",measuredRubles:30)
        for coverage:Double? in [nil,0,-0.5,1,1.2,.nan,.infinity] {
            s.costCoverage=coverage;XCTAssertNil(s.projectedRubles)
        }
        s.costCoverage=0.5
        for measured:Double? in [nil,0,-1,.nan,.infinity,Double.greatestFiniteMagnitude] {
            s.measuredRubles=measured;XCTAssertNil(s.projectedRubles)
        }
    }

}
