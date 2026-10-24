import Foundation
import MeterCore

extension MeterCoreTests {
    func testQuotaRefreshBackoffAndRecovery() {
        let now = Date(timeIntervalSince1970: 1_000)
        let forbidden = CodexServiceError(method: "account/rateLimits/read", code: -32603, message: "request failed: 403 Forbidden; content-type=text/html; body=<html>private-page</html>")
        XCTAssertEqual(forbidden.httpStatus, 403)
        XCTAssertFalse(forbidden.retryable)
        XCTAssertFalse(forbidden.requiresLogin)
        XCTAssertFalse(forbidden.localizedDescription.contains("private-page"))
        var schedule = QuotaRefreshSchedule()
        XCTAssertTrue(schedule.isDue(at: now))
        schedule.failed(forbidden, at: now)
        XCTAssertFalse(schedule.isDue(at: now.addingTimeInterval(299)))
        XCTAssertTrue(schedule.isDue(at: now.addingTimeInterval(300)))
        schedule.failed(forbidden, at: now)
        XCTAssertEqual(schedule.nextAttempt, now.addingTimeInterval(600))
        for _ in 0..<20 { schedule.failed(forbidden, at: now) }
        XCTAssertEqual(schedule.nextAttempt, now.addingTimeInterval(900))
        schedule.succeeded(at: now)
        XCTAssertTrue(schedule.isDue(at: now))
        schedule.failed(CodexServiceError(method:"test",code:-32098,message:"timeout"),at:now)
        XCTAssertEqual(schedule.nextAttempt, now.addingTimeInterval(60))
        schedule.failed(CodexServiceError(method:"test",code:-32603,message:"429 Too Many Requests"),at:now)
        XCTAssertEqual(schedule.nextAttempt, now.addingTimeInterval(120))
    }
    func testCodexHTTPFailuresRemainDistinct() {
        for (code, message, status, retryable) in [
            (-32603, "request failed: 503 Service Unavailable", 503, true),
            (-32603, "status code 429", 429, false),
            (-32603, "HTTP/2 403", 403, false),
            (403, "forbidden", 403, false),
            (-32603, "401 Unauthorized", 401, false)
        ] {
            let error = CodexServiceError(method:"test",code:code,message:message)
            XCTAssertEqual(error.httpStatus, status)
            XCTAssertEqual(error.retryable, retryable)
        }
        let error = CodexServiceError(method:"test",code:-32603,message:"temporary upstream failure; Bearer secret")
        XCTAssertTrue(error.retryable)
        XCTAssertFalse(error.localizedDescription.contains("secret"))
        let longJWT = "eyJ" + String(repeating:"a",count:1700) + ".bbb.ccc"
        let longError = CodexServiceError(method:"test",code:-32603,message:longJWT)
        XCTAssertFalse(longError.message.contains("eyJ"))
    }
}
