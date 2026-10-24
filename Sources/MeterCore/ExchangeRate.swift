import Foundation

/// Rubles per one US dollar, with the effective date published by the Bank of Russia.
public struct USDExchangeRate: Codable, Equatable {
    public let rublesPerDollar: Double
    public let effectiveDate: Date
    public let fetchedAt: Date
    public static let cacheKey = "usdExchangeRate"

    public init(rublesPerDollar: Double, effectiveDate: Date, fetchedAt: Date = Date()) {
        self.rublesPerDollar = rublesPerDollar
        self.effectiveDate = effectiveDate
        self.fetchedAt = fetchedAt
    }
    public var valid: Bool {
        rublesPerDollar.isFinite && rublesPerDollar > 0 &&
        effectiveDate.timeIntervalSince1970.isFinite && fetchedAt.timeIntervalSince1970.isFinite &&
        effectiveDate <= fetchedAt
    }
    public func dollars(for rubles: Double?) -> Double? {
        guard valid, let rubles, rubles.isFinite, rubles >= 0 else { return nil }
        let result = rubles / rublesPerDollar
        return result.isFinite ? result : nil
    }
    public func isStale(at now: Date = Date()) -> Bool {
        !valid || now < fetchedAt || now.timeIntervalSince(fetchedAt) >= 86400 ||
        now.timeIntervalSince(effectiveDate) >= 7 * 86400
    }
    public static func cached(in db: Database) throws -> Self? {
        guard let json = try db.value(cacheKey), let rate = try? Codec.decode(Self.self, json), rate.valid else { return nil }
        return rate
    }
    public func save(in db: Database) throws {
        guard valid else { throw MeterError("Некорректный курс USD") }
        try db.set(Self.cacheKey, Codec.encode(self))
    }
}

public enum CBRExchangeRateClient {
    public static func request(at now: Date = Date()) -> URLRequest {
        let formatter = dateFormatter("dd/MM/yyyy")
        var components = URLComponents(string: "https://www.cbr.ru/scripts/XML_daily.asp")!
        // The undated feed may already contain tomorrow's rate.
        components.queryItems = [URLQueryItem(name: "date_req", value: formatter.string(from: now))]
        return URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }
    public static func fetch(session: URLSession = .shared, now: Date = Date()) async throws -> USDExchangeRate {
        let (data, response) = try await session.data(for: request(at: now))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MeterError("Не удалось получить курс USD от ЦБ РФ")
        }
        return try parse(data, fetchedAt: now)
    }
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> USDExchangeRate {
        let delegate = RateParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let date = delegate.date, let value = delegate.value,
              let nominal = delegate.nominal, nominal.isFinite, nominal > 0 else {
            throw MeterError("ЦБ РФ вернул некорректный курс USD")
        }
        let rate = USDExchangeRate(rublesPerDollar: value / nominal, effectiveDate: date, fetchedAt: fetchedAt)
        guard rate.valid else { throw MeterError("ЦБ РФ вернул некорректный курс USD") }
        return rate
    }
    fileprivate static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

private final class RateParser: NSObject, XMLParserDelegate {
    var date: Date?
    var value: Double?
    var nominal: Double?
    private var fields: [String: String] = [:]
    private var text = ""
    private var inCurrency = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if name == "ValCurs", let raw = attributes["Date"] { date = CBRExchangeRateClient.dateFormatter("dd.MM.yyyy").date(from: raw) }
        if name == "Valute" { fields = [:]; inCurrency = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inCurrency else { return }
        fields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "Valute" {
            if fields["CharCode"] == "USD" {
                value = number(fields["Value"])
                nominal = number(fields["Nominal"])
            }
            inCurrency = false
        }
    }
    private func number(_ raw: String?) -> Double? {
        raw.flatMap { Double($0.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }) }
    }
}
