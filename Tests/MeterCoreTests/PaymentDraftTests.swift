import Foundation
import MeterCore

extension MeterCoreTests {
    private var billingCalendar:Calendar {
        var result=Calendar(identifier:.gregorian)
        result.timeZone=TimeZone(identifier:"Europe/Moscow")!
        return result
    }
    private func billingDate(_ year:Int,_ month:Int,_ day:Int,_ hour:Int=0)->Date {
        billingCalendar.date(from:DateComponents(year:year,month:month,day:day,hour:hour))!
    }
    func testFirstPaymentDraftStartsTodayWithoutCopyingMoney() {
        let draft=Payment.nextDraft(after:[],now:billingDate(2026,9,14,16),calendar:billingCalendar)
        XCTAssertEqual(draft.start,billingDate(2026,9,14))
        XCTAssertEqual(draft.end,billingDate(2026,10,14))
        XCTAssertEqual(draft.amount,0)
    }
    func testPaymentDraftUsesLatestEndRegardlessOfOrderOrToday() {
        let latest=Payment(amount:6000,start:billingDate(2026,9,7),end:billingDate(2026,10,7))
        let older=Payment(amount:5000,start:billingDate(2026,8,7),end:billingDate(2026,9,7))
        for now in [billingDate(2026,9,14),billingDate(2027,1,1)] {
            let draft=Payment.nextDraft(after:[latest,older],now:now,calendar:billingCalendar)
            XCTAssertEqual(draft.start,latest.end)
            XCTAssertEqual(draft.end,billingDate(2026,11,7))
            XCTAssertEqual(draft.amount,0)
            XCTAssertNotEqual(draft.id,latest.id)
        }
    }
    func testMultiMonthPaymentDraftSuggestsOnlyOneFollowingMonth() throws {
        let paid=Payment(amount:15000,start:billingDate(2026,10,7),end:billingDate(2027,1,7))
        let draft=Payment.nextDraft(after:[paid],calendar:billingCalendar)
        XCTAssertEqual(draft.start,billingDate(2027,1,7))
        XCTAssertEqual(draft.end,billingDate(2027,2,7))
        let db=try database();try db.savePayment(paid)
        var filled=draft;filled.amount=5000
        try db.savePayment(filled)
        XCTAssertEqual(try db.payments().count,2)
    }
    func testPaymentDraftHandlesShortMonthsAndLeapYearsWithoutDayDrift() {
        for year in [2024,2026] {
            let februaryLast=year==2024 ? 29:28
            for day in [28,29,30,31] {
                let january=Payment(amount:1,start:billingDate(year,1,day),end:billingDate(year,2,min(day,februaryLast)))
                let march=Payment.nextDraft(after:[january],calendar:billingCalendar)
                XCTAssertEqual(march.start,january.end)
                XCTAssertEqual(march.end,billingDate(year,3,day))
                let april=Payment.nextDraft(after:[march],calendar:billingCalendar)
                XCTAssertEqual(april.end,billingDate(year,4,min(day,30)))
                let may=Payment.nextDraft(after:[april],calendar:billingCalendar)
                XCTAssertEqual(may.end,billingDate(year,5,day))
            }
        }
    }
}
