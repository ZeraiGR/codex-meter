import Foundation

public struct MeterError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Codec {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}

public struct QuotaWindow: Codable, Equatable {
    public var usedPercent: Double
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var duration: Double { Double(windowDurationMins ?? 0) * 60 }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    /// Progress of the server's current quota window, independent of calendar weeks.
    /// After expiry we wait for a new reset timestamp instead of inventing a window.
    public func elapsedPercent(at date:Date)->Double? {
        guard duration>0,let reset=resetsAt,reset.isFinite,date.timeIntervalSince1970.isFinite else { return nil }
        let start=reset-duration,now=date.timeIntervalSince1970
        guard now>=start,now<reset else { return nil }
        return max(0,min(100,(now-start)/duration*100))
    }
    public var label: String {
        guard let mins = windowDurationMins else { return "Период квоты" }
        if mins == 10080 { return "Неделя" }
        if mins % 1440 == 0 { return "\(mins / 1440) дн." }
        if mins % 60 == 0 { return "\(mins / 60) ч" }
        return "\(mins) мин"
    }
    public func valid(at date: Date) -> Bool { duration > 0 && (resetsAt ?? 0) > date.timeIntervalSince1970 }
}

public struct QuotaBucket: Codable, Identifiable {
    public var limitId: String?
    public var limitName: String?
    public var primary: QuotaWindow?
    public var secondary: QuotaWindow?
    public var planType: String?
    public var id: String { limitId ?? "codex" }
    public var title: String { limitName ?? (id == "codex" ? "Codex" : id) }
    public var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    public init(limitId: String? = "codex", limitName: String? = nil, primary: QuotaWindow?, secondary: QuotaWindow? = nil, planType: String? = nil) {
        self.limitId = limitId; self.limitName = limitName; self.primary = primary; self.secondary = secondary; self.planType = planType
    }
}

public struct DailyUsage: Codable, Identifiable {
    public var startDate: String
    public var tokens: Int64
    public var id: String { startDate }
}

public struct AccountSnapshot: Codable {
    public var accountKey: String
    public var plan: String
    public var fetchedAt: Date
    public var buckets: [QuotaBucket]
    public var daily: [DailyUsage]?
    public var lifetimeTokens: Int64?
    public var usageError: String?
    public var main: QuotaBucket? { buckets.first { $0.id == "codex" } }
    public var moneyWindow: QuotaWindow? { main?.windows.filter { $0.duration > 0 }.max { $0.duration < $1.duration } }
    public init(accountKey: String, plan: String = "", fetchedAt: Date = Date(), buckets: [QuotaBucket], daily: [DailyUsage]? = nil, lifetimeTokens: Int64? = nil, usageError: String? = nil) {
        self.accountKey = accountKey; self.plan = plan; self.fetchedAt = fetchedAt; self.buckets = buckets
        self.daily = daily; self.lifetimeTokens = lifetimeTokens; self.usageError = usageError
    }
    public func fresh(at now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) >= -60 && now.timeIntervalSince(fetchedAt) < 180 }
}

public struct Payment: Codable, Identifiable {
    public var id: String
    public var amount: Double
    public var start: Date
    public var end: Date
    public init(id: String = UUID().uuidString, amount: Double, start: Date, end: Date) {
        self.id = id; self.amount = amount; self.start = start; self.end = end
    }
    public static func nextDraft(after payments:[Payment],now:Date = Date(),calendar:Calendar = .current)->Payment {
        let latest=payments.max { $0.end < $1.end }
        let start=calendar.startOfDay(for:latest?.end ?? now)
        let following=calendar.date(byAdding:.month,value:1,to:start) ?? start
        var end=following
        // Preserve a billing day clipped by February or another short month:
        // Jan 31–Feb 28 is followed by Feb 28–Mar 31, not a permanent move to the 28th.
        if let latest,
           let days=calendar.range(of:.day,in:.month,for:start),
           calendar.component(.day,from:start)==days.count {
            let anchor=calendar.component(.day,from:latest.start)
            if anchor>calendar.component(.day,from:start),
               let nextDays=calendar.range(of:.day,in:.month,for:following),
               let month=calendar.dateInterval(of:.month,for:following)?.start {
                end=calendar.date(byAdding:.day,value:min(anchor,nextDays.count)-1,to:month) ?? following
            }
        }
        return Payment(amount:0,start:start,end:end)
    }
    public var seconds: Double { end.timeIntervalSince(start) }
    public func contains(_ date: Date) -> Bool { date >= start && date < end }
    public func cost(points: Double, windowSeconds: Double) -> Double {
        guard seconds > 0, amount.isFinite, points.isFinite, windowSeconds > 0 else { return 0 }
        return amount * windowSeconds / seconds * max(0, points) / 100
    }
    public func available(window: QuotaWindow, now: Date) -> (current: Double, future: Double)? {
        guard contains(now), window.valid(at: now), let reset = window.resetDate else { return nil }
        let windowStart = reset.addingTimeInterval(-window.duration)
        let overlap = max(0, min(end, reset).timeIntervalSince(max(start, windowStart)))
        let current = amount * overlap / seconds * window.remaining / 100
        let future = amount * max(0, end.timeIntervalSince(max(start, reset))) / seconds
        return (current, future)
    }
}

public struct TokenCount: Codable, Equatable {
    public var input: Int64 = 0
    public var cached: Int64 = 0
    public var output: Int64 = 0
    public var reasoning: Int64 = 0
    public var total: Int64 { input + output }
    public init(input: Int64 = 0, cached: Int64 = 0, output: Int64 = 0, reasoning: Int64 = 0) {
        self.input = input; self.cached = cached; self.output = output; self.reasoning = reasoning
    }
    public static func + (l: Self, r: Self) -> Self {
        .init(input: l.input + r.input, cached: l.cached + r.cached, output: l.output + r.output, reasoning: l.reasoning + r.reasoning)
    }
    public func delta(from old: Self) -> Self {
        // A reset is a new counter baseline, never a negative charge.
        if total < old.total { return self }
        return .init(input: max(0, input-old.input), cached: max(0,cached-old.cached), output:max(0,output-old.output), reasoning:max(0,reasoning-old.reasoning))
    }
}

public struct RunRecord: Codable, Identifiable {
    public var id: String
    public var thread: String
    public var parentThread: String?
    public var started: Date
    public var ended: Date?
    public var tokens: TokenCount
    public var model: String
    public var effort: String
    public var title: String
    public var outcome: String
    public var taskID: String?
    public var sourcePath: String?
    public var workingDirectory: String?
    public var category: String?
    public var preview: String?
    public var messageCount: Int?
    public var projectName: String { workingDirectory.map { URL(fileURLWithPath:$0).lastPathComponent } ?? "Проект неизвестен" }
    public var isService: Bool { category == "service" }
    public var categoryLabel: String { isService ? "Служебная проверка":category == "agent" ? "Вспомогательный агент":"Переписка" }
    public var tokenEvents: [TokenEvent] = []
    public init(id: String, thread: String, parentThread: String? = nil, started: Date, ended: Date? = nil, tokens: TokenCount = .init(), model: String = "", effort: String = "", title: String = "Запуск Codex", outcome: String = "running", taskID: String? = nil, tokenEvents: [TokenEvent] = []) {
        self.id=id;self.thread=thread;self.parentThread=parentThread;self.started=started;self.ended=ended
        self.tokens=tokens;self.model=model;self.effort=effort;self.title=title;self.outcome=outcome;self.taskID=taskID;self.tokenEvents=tokenEvents
    }
}
public struct TokenEvent: Codable {
    public var date: Date; public var tokens: TokenCount
    public init(date:Date,tokens:TokenCount){self.date=date;self.tokens=tokens}
}

public struct WorkTask: Codable, Identifiable {
    public var id: String
    public var title: String
    public var kind: String
    public var status: String
    public var created: Date
    public var finished: Date?
    public var skillVersion: String?
    public init(id: String = UUID().uuidString, title: String, kind: String, status: String = "active", created: Date = Date(), finished: Date? = nil, skillVersion: String? = nil) {
        self.id=id;self.title=title;self.kind=kind;self.status=status;self.created=created;self.finished=finished;self.skillVersion=skillVersion
    }
}

public struct WeeklyQuotaUsage: Codable, Equatable {
    public var points:Double
    public var coverage:Double
    public var windowCount:Int
    public init(points:Double,coverage:Double,windowCount:Int) {self.points=points;self.coverage=coverage;self.windowCount=windowCount}
    public var complete:Bool {coverage>=0.99}
}

public struct TaskSummary: Identifiable {
    public var task: WorkTask
    public var runs: [RunRecord]
    public var quotaPoints: Double?
    public var rubles: Double?
    public var quotaQuality: String
    public var measuredRubles: Double?
    public var costCoverage: Double?
    public var weeklyQuota:WeeklyQuotaUsage?
    public init(task:WorkTask,runs:[RunRecord],quotaPoints:Double?,rubles:Double?,quotaQuality:String,measuredRubles:Double? = nil,costCoverage:Double? = nil,weeklyQuota:WeeklyQuotaUsage? = nil) {
        self.task=task;self.runs=runs;self.quotaPoints=quotaPoints;self.rubles=rubles;self.quotaQuality=quotaQuality;self.measuredRubles=measuredRubles;self.costCoverage=costCoverage
        self.weeklyQuota=weeklyQuota
    }
    /// Extrapolation is separate from measured cost and never used as a quota observation.
    public var projectedRubles: Double? {
        guard rubles==nil,let measured=measuredRubles,measured.isFinite,measured>0,
              let coverage=costCoverage,coverage.isFinite,coverage>0,coverage<1 else{return nil}
        let total=measured/coverage
        return total.isFinite ? total:nil
    }
    public var id: String { task.id }
    public var tokens: TokenCount { runs.reduce(.init()) { $0 + $1.tokens } }
    public var activeSeconds: Double {
        Self.unionSeconds(runs.map { ($0.started, $0.ended ?? Date()) })
    }
    public var wallSeconds: Double {
        let ongoing=["active","paused"].contains(task.status) || runs.contains{$0.ended==nil}
        let end=ongoing ? Date():max(task.finished ?? task.created,runs.compactMap(\.ended).max() ?? task.created)
        return max(0,end.timeIntervalSince(min(task.created,runs.map(\.started).min() ?? task.created)))
    }
    public var models: [String] { Array(Set(runs.map(\.model).filter { !$0.isEmpty })).sorted() }
    public static func unionSeconds(_ intervals: [(Date,Date)]) -> Double {
        let valid = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = valid.first else { return 0 }
        var result: Double = 0
        for next in valid.dropFirst() {
            if next.0 <= current.1 { current.1 = max(current.1, next.1) }
            else { result += current.1.timeIntervalSince(current.0); current = next }
        }
        return result + current.1.timeIntervalSince(current.0)
    }
}

public struct QuotaObservation: Codable {
    public var account: String; public var date: Date; public var window: QuotaWindow
    public init(account:String,date:Date,window:QuotaWindow){self.account=account;self.date=date;self.window=window}
}

public struct Forecast: Codable {
    public var kind: String
    public var samples: Int
    public var tokenMedian: Double?
    public var tokenUpper: Double?
    public var secondsMedian: Double?
    public var quotaUpper: Double?
    public var availablePercent: Double?
    public var rublesUpper: Double?
    public var risk: String
    public var explanation: String
}

public enum Predictor {
    public static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted=values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[min(sorted.count-1, max(0, Int(ceil(Double(sorted.count)*fraction))-1))]
    }
    public static func estimate(kind: String, history: [TaskSummary], snapshot: AccountSnapshot?, payment: Payment?, model: String? = nil, now: Date = Date()) -> Forecast {
        let relevant=history.filter { $0.task.kind == kind && $0.task.status == "completed" && !$0.runs.isEmpty && (model == nil || $0.models == [model!]) }
        let tokens=relevant.map { Double($0.tokens.total) }
        let points=relevant.filter{!$0.quotaQuality.hasPrefix("Грубая")}.compactMap(\.quotaPoints)
        let window=snapshot?.moneyWindow
        let available = snapshot?.fresh(at:now) == true && window?.valid(at:now) == true ? window?.remaining : nil
        let upper = points.count >= 3 ? percentile(points,0.9).map { $0 * 1.2 } : nil
        let risk: String
        let reason: String
        if relevant.count < 3 { risk="unknown";reason="Меньше трёх завершённых похожих задач. Надёжного прогноза пока нет." }
        else if available == nil { risk="unknown";reason="Нет свежего остатка квоты. Обновите подключение." }
        else if upper == nil { risk="unknown";reason="История токенов есть; измерений доли квоты недостаточно." }
        else if upper! >= available! { risk="high";reason="Оценка с запасом достигает доступного остатка. Квоты может не хватить." }
        else if upper! >= available! * 0.7 { risk="caution";reason="Задача может использовать большую часть остатка. Учтите параллельную работу." }
        else { risk="low";reason="По доступной истории задача помещается в остаток с запасом. Это оценка, не гарантия." }
        return Forecast(kind:kind,samples:relevant.count,tokenMedian:percentile(tokens,0.5),tokenUpper:percentile(tokens,0.9).map{$0*1.2},secondsMedian:percentile(relevant.map(\.activeSeconds),0.5),quotaUpper:upper,availablePercent:available,rublesUpper:upper.flatMap { p in window.flatMap { w in payment.map{$0.cost(points:p,windowSeconds:w.duration)} } },risk:risk,explanation:reason)
    }
}
