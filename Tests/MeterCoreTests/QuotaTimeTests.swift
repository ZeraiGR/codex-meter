import Foundation
import MeterCore

extension MeterCoreTests {
    func testQuotaTimeUsesResetWindowAndAdvancesWithoutQuotaChanges() throws {
        let reset=epoch.addingTimeInterval(7*day)
        let window=QuotaWindow(usedPercent:37,windowDurationMins:10080,resetsAt:reset.timeIntervalSince1970)
        XCTAssertEqual(try XCTUnwrap(window.elapsedPercent(at:epoch)),0)
        XCTAssertEqual(try XCTUnwrap(window.elapsedPercent(at:epoch.addingTimeInterval(7*day*0.31))),31,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(window.elapsedPercent(at:epoch.addingTimeInterval(7*day*0.5))),50,accuracy:0.000001)
        XCTAssertTrue(try XCTUnwrap(window.elapsedPercent(at:reset.addingTimeInterval(-1)))<100)
        let short=QuotaWindow(usedPercent:0,windowDurationMins:300,resetsAt:epoch.addingTimeInterval(18000).timeIntervalSince1970)
        XCTAssertEqual(try XCTUnwrap(short.elapsedPercent(at:epoch.addingTimeInterval(9000))),50)
    }
    func testQuotaTimeDoesNotInventMissingOrExpiredWindows() {
        let reset=epoch.addingTimeInterval(7*day)
        let window=QuotaWindow(usedPercent:37,windowDurationMins:10080,resetsAt:reset.timeIntervalSince1970)
        XCTAssertNil(window.elapsedPercent(at:epoch.addingTimeInterval(-1)))
        XCTAssertNil(window.elapsedPercent(at:reset))
        XCTAssertNil(window.elapsedPercent(at:reset.addingTimeInterval(7*day)))
        for duration in [nil,0,-100] as [Int?] {
            XCTAssertNil(QuotaWindow(usedPercent:0,windowDurationMins:duration,resetsAt:reset.timeIntervalSince1970).elapsedPercent(at:epoch))
        }
        for end in [nil,Double.nan,Double.infinity] as [Double?] {
            XCTAssertNil(QuotaWindow(usedPercent:0,windowDurationMins:10080,resetsAt:end).elapsedPercent(at:epoch))
        }
    }
}
