import Foundation

public enum Attribution {
    public struct Result {
        public var points: Double?
        public var rubles: Double?
        public var quality: String
        public var measuredRubles: Double? = nil
        public var costCoverage: Double? = nil
        public var weeklyQuota:WeeklyQuotaUsage? = nil
    }
    public static func compute(runs: [RunRecord], observations: [QuotaObservation], payments: [Payment]) -> [String:Result] {
        struct Acc { var points=0.0; var rubles=0.0; var covered:Int64=0;var priced:Int64=0;var pricedWeight=0.0;var concurrent=false;var windows=Set<Int>();var accounts=Set<String>();var weeklyResets:[Double]=[] }
        var totals:[String:Int64]=[:], accum:[String:Acc]=[:]
        for r in runs { if let id=r.taskID { totals[id,default:0] += r.tokens.total } }
        guard observations.count>1 else { return [:] }
        for (a,b) in zip(observations,observations.dropFirst()) {
            let delta=b.window.usedPercent-a.window.usedPercent
            guard a.account==b.account, AlertPolicy.sameWindow(a.window,b.window),
                  a.window.windowDurationMins==b.window.windowDurationMins,
                  b.date>a.date,b.date.timeIntervalSince(a.date)<=180,
                  a.window.valid(at:a.date),b.window.valid(at:b.date),delta>=0,delta<=100 else { continue }
            let activity=runs.filter { $0.started<=b.date && ($0.ended ?? b.date)>=a.date }
            var weights:[String:Int64]=[:];var allWeight:Int64=0
            for run in activity {
                let count=run.tokenEvents.filter{$0.date>a.date && $0.date<=b.date}.reduce(Int64(0)){$0+$1.tokens.total}
                allWeight += count
                if let id=run.taskID { weights[id,default:0] += count }
            }
            guard allWeight>0 else { continue }
            let concurrent=Set(activity.map{$0.taskID ?? "unassigned:\($0.thread)"}).count>1
            for (id,count) in weights where count>0 {
                var acc=accum[id] ?? Acc()
                let part=delta * Double(count)/Double(allWeight)
                acc.points += part;acc.covered += count;acc.concurrent = acc.concurrent || concurrent
                acc.windows.insert(b.window.windowDurationMins ?? 0);acc.accounts.insert(b.account)
                if b.window.windowDurationMins==10080,let reset=b.window.resetsAt,
                   !acc.weeklyResets.contains(where:{abs($0-reset)<=90}) {acc.weeklyResets.append(reset)}
                // Charge each part at its payment-period rate. No payment => unknown cost, never zero.
                let span=b.date.timeIntervalSince(a.date)
                var coveredSeconds=0.0
                for bill in payments {
                    let overlap=max(0,min(b.date,bill.end).timeIntervalSince(max(a.date,bill.start)))
                    if overlap>0 {
                        coveredSeconds += overlap
                        acc.pricedWeight += Double(count)*overlap/span
                        acc.rubles += bill.cost(points:part*overlap/span,windowSeconds:b.window.duration)
                    }
                }
                if coveredSeconds>=span-0.001 { acc.priced += count }
                accum[id]=acc
            }
        }
        var result:[String:Result]=[:]
        for (id,total) in totals where total>0 {
            guard let a=accum[id] else { continue }
            let coverage=Double(a.covered)/Double(total)
            if a.accounts.count>1 || a.windows.count>1 {
                result[id]=Result(points:nil,rubles:nil,quality:"Менялись аккаунт или условия квоты")
            } else if coverage<0.99 {
                result[id]=Result(points:nil,rubles:nil,quality:"Измерено \(Int(min(100,coverage*100)))% токенов: не хватает снимков квоты"+(a.concurrent ? ". Параллельный расход распределён по токенам":""),measuredRubles:a.rubles>0 ? a.rubles:nil,costCoverage:min(1,a.pricedWeight/Double(total)))
            } else if a.points==0 {
                result[id]=Result(points:nil,rubles:nil,quality:"Расход ниже разрешения счётчика квоты")
            } else {
                result[id]=Result(points:a.points,rubles:a.priced>=total ? a.rubles:nil,quality:a.concurrent ? "Грубая оценка: параллельный расход распределён по токенам" : "Оценка по изменению квоты; округление сервера",measuredRubles:a.rubles>0 ? a.rubles:nil,costCoverage:min(1,a.pricedWeight/Double(total)))
            }
            if a.accounts.count==1,a.windows==Set([10080]),a.points>0 {
                result[id]?.weeklyQuota=WeeklyQuotaUsage(points:a.points,coverage:min(1,coverage),windowCount:a.weeklyResets.count)
            }
        }
        return result
    }
}

public enum AlertPolicy {
    public static let defaults:[Int]=[50,80,90,95]
    public static func sameWindow(_ a:QuotaWindow,_ b:QuotaWindow) -> Bool {
        guard let x=a.resetsAt,let y=b.resetsAt,a.windowDurationMins==b.windowDurationMins else{return false}
        return abs(x-y)<=90
    }
    public static func expiring(window:QuotaWindow,days:Int,minimumRemaining:Int,now:Date) -> Bool {
        guard window.valid(at:now),let reset=window.resetDate,days>0 else{return false}
        return reset.timeIntervalSince(now)<=Double(days)*86400 && window.remaining>=Double(minimumRemaining)
    }
    public static func pending(window:QuotaWindow,thresholds:[Int],sent:Set<Int>,now:Date) -> [Int] {
        guard window.valid(at:now) else { return [] }
        // One most relevant alert after first launch / sleep, mark lower thresholds as seen.
        return thresholds.filter{$0>0 && $0<100 && Double($0)<=window.usedPercent && !sent.contains($0)}.sorted()
    }
    public static func key(account:String,bucket:String,window:QuotaWindow) -> String {
        "alert:\(account):\(bucket):\(window.windowDurationMins ?? 0):\(Int(window.resetsAt ?? 0))"
    }
}
