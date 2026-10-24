import Foundation
import MeterCore

extension MeterCoreTests {
    func testQuotaEvidenceLabelsMovingZeroAndKeepsRawDate() throws {
        let window=QuotaWindow(usedPercent:0,windowDurationMins:10080,resetsAt:epoch.timeIntervalSince1970+7*day)
        let snapshot=AccountSnapshot(accountKey:"demo",fetchedAt:epoch,buckets:[QuotaBucket(primary:window)])
        let result=snapshot.withQuotaEvidence(previous:nil)
        let marked=try XCTUnwrap(result.moneyWindow)
        XCTAssertEqual(marked.resetsAt,window.resetsAt)
        XCTAssertTrue(marked.resetIsProvisional==true)
        XCTAssertNil(marked.elapsedPercent(at:epoch))
        XCTAssertTrue(!AlertPolicy.expiring(window:marked,days:8,minimumRemaining:1,now:epoch))
        var next=snapshot;next.fetchedAt=epoch.addingTimeInterval(180)
        next.buckets[0].primary?.resetsAt=window.resetsAt!+180
        XCTAssertNil(next.withQuotaEvidence(previous:result).weeklyResetChange)
        next.buckets[0].primary?.usedPercent=1
        XCTAssertTrue(next.withQuotaEvidence(previous:result).moneyWindow?.resetIsProvisional==false)
    }
    func testQuotaEvidenceReportsChangesWithoutClaimingExactReset() throws {
        let old=AccountSnapshot(accountKey:"demo",fetchedAt:epoch,buckets:[QuotaBucket(primary:QuotaWindow(usedPercent:40,windowDurationMins:10080,resetsAt:epoch.timeIntervalSince1970+day))])
        var next=old;next.fetchedAt=epoch.addingTimeInterval(3600)
        next.buckets[0].primary?.resetsAt=epoch.timeIntervalSince1970+5*day
        next.buckets[0].primary?.usedPercent=2
        let result=next.withQuotaEvidence(previous:old)
        let change=try XCTUnwrap(result.weeklyResetChange)
        XCTAssertEqual(change.previousObservation,epoch)
        XCTAssertEqual(change.observedAt,next.fetchedAt)
        XCTAssertTrue(change.usageDropped)
        let jittered=next.buckets[0].primary!.resetsAt!+1
        next.buckets[0].primary?.resetsAt=jittered
        XCTAssertEqual(next.withQuotaEvidence(previous:result).weeklyResetChange?.observedAt,change.observedAt)
        next.accountKey="different"
        XCTAssertNil(next.withQuotaEvidence(previous:old).weeklyResetChange)
        let decoded=try Codec.decode(AccountSnapshot.self,Codec.encode(result))
        XCTAssertEqual(decoded.weeklyResetChange?.reportedReset,change.reportedReset)
    }
}
