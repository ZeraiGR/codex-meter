import Foundation
import MeterCore

private let rateXML = """
<?xml version="1.0" encoding="UTF-8"?>
<ValCurs Date="19.09.2026"><Valute><CharCode>EUR</CharCode><Nominal>1</Nominal><Value>95,00</Value></Valute><Valute><CharCode>USD</CharCode><Nominal>10</Nominal><Value>825,50</Value></Valute></ValCurs>
"""
private let rateNow = ISO8601DateFormatter().date(from:"2026-09-20T12:00:00Z")!
private final class RateURLProtocol: URLProtocol {
    static var status = 200
    static var data = Data(rateXML.utf8)
    static var offline = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.offline {client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet));return}
        let response=HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension MeterCoreTests {
    func testUSDExchangeRateParsingConversionAndCache() throws {
        let rate=try CBRExchangeRateClient.parse(Data(rateXML.utf8),fetchedAt:rateNow)
        XCTAssertEqual(rate.rublesPerDollar,82.55,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(rate.dollars(for:165.1)),2,accuracy:0.000001)
        XCTAssertEqual(rate.dollars(for:0),0)
        for amount:Double? in [nil,-1,.infinity,.nan] {XCTAssertNil(rate.dollars(for:amount))}
        let db=try database()
        XCTAssertNil(try USDExchangeRate.cached(in:db))
        try rate.save(in:db)
        XCTAssertEqual(try USDExchangeRate.cached(in:db),rate)
        try db.set(USDExchangeRate.cacheKey,"corrupt")
        XCTAssertNil(try USDExchangeRate.cached(in:db))
        let invalid=USDExchangeRate(rublesPerDollar:0,effectiveDate:rate.effectiveDate,fetchedAt:rateNow)
        try db.set(USDExchangeRate.cacheKey,Codec.encode(invalid))
        XCTAssertNil(try USDExchangeRate.cached(in:db))
        XCTAssertThrowsError(try invalid.save(in:db))
        XCTAssertNil(invalid.dollars(for:10))
    }
    func testUSDExchangeRateRejectsInvalidResponses() {
        for xml in ["<html>unavailable</html>","<ValCurs>",rateXML.replacingOccurrences(of:"USD",with:"GBP"),
                    rateXML.replacingOccurrences(of:"825,50",with:"0"),rateXML.replacingOccurrences(of:"825,50",with:"nan"),
                    rateXML.replacingOccurrences(of:"825,50",with:"-1"),rateXML.replacingOccurrences(of:"<Nominal>10",with:"<Nominal>0"),
                    rateXML.replacingOccurrences(of:"19.09.2026",with:"21.09.2026"),rateXML.replacingOccurrences(of:"19.09.2026",with:"invalid")] {
            XCTAssertThrowsError(try CBRExchangeRateClient.parse(Data(xml.utf8),fetchedAt:rateNow))
        }
    }
    func testUSDExchangeRateFreshnessAndMoscowDate() throws {
        let rate=try CBRExchangeRateClient.parse(Data(rateXML.utf8),fetchedAt:rateNow)
        XCTAssertFalse(rate.isStale(at:rateNow)) // Sunday uses the last effective rate.
        XCTAssertTrue(rate.isStale(at:rateNow.addingTimeInterval(86400)))
        XCTAssertTrue(rate.isStale(at:rateNow.addingTimeInterval(-1)))
        let old=USDExchangeRate(rublesPerDollar:80,effectiveDate:rateNow.addingTimeInterval(-8*86400),fetchedAt:rateNow)
        XCTAssertTrue(old.isStale(at:rateNow))
        let utcEvening=ISO8601DateFormatter().date(from:"2026-09-20T22:00:00Z")!
        let request=CBRExchangeRateClient.request(at:utcEvening)
        let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems
        XCTAssertEqual(query?.first?.value,"21/09/2026")
    }
    func testUSDExchangeRateNetworkFailuresPreserveCache() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RateURLProtocol.self]
        let session=URLSession(configuration:config)
        defer {session.invalidateAndCancel()}
        let db=try database()
        let rate=try await CBRExchangeRateClient.fetch(session:session,now:rateNow)
        try rate.save(in:db)
        for mode in ["http","html","offline"] {
            RateURLProtocol.status=mode == "http" ? 503:200
            RateURLProtocol.data=mode == "html" ? Data("<html>failure</html>".utf8):Data(rateXML.utf8)
            RateURLProtocol.offline=mode == "offline"
            do { _ = try await CBRExchangeRateClient.fetch(session:session,now:rateNow);XCTAssertTrue(false) }
            catch {XCTAssertEqual(try USDExchangeRate.cached(in:db),rate)}
        }
    }
}
