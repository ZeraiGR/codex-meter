import Foundation

public enum TaskSort:String,CaseIterable {case recent,tokens,time,cost,quota,title}

public enum TaskListQuery {
    private static func normalized(_ text:String)->String {text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"ru_RU"))}
    public static func apply(_ summaries:[TaskSummary],query:String="",status:String="",kind:String="",sort:TaskSort = .recent,ascending:Bool=false)->[TaskSummary] {
        let words=normalized(query).split(whereSeparator:{$0.isWhitespace}),kind=normalized(kind.trimmingCharacters(in:.whitespacesAndNewlines))
        // Compute metrics once per task, not for every comparison in the sort.
        let rows=summaries.filter { s in
            (status.isEmpty || s.task.status==status) && (kind.isEmpty || normalized(s.task.kind).contains(kind)) && words.allSatisfy {normalized(s.task.title+" "+s.task.kind).contains($0)}
        }.map { s -> (summary:TaskSummary,key:Double?,title:String) in
            let key:Double?
            switch sort {
            case .recent: key=max(s.task.created,s.task.finished ?? s.task.created,s.runs.map{$0.ended ?? $0.started}.max() ?? s.task.created).timeIntervalSince1970
            case .tokens: key=Double(s.tokens.total)
            case .time: key=s.activeSeconds
            case .cost: key=s.rubles ?? s.measuredRubles
            case .quota: key=s.weeklyQuota?.points
            case .title: key=nil
            }
            return (s,key?.isFinite==true ? key:nil,normalized(s.task.title))
        }
        return rows.sorted { a,b in
            if sort != .title {
                if let x=a.key,let y=b.key,x != y {return ascending ? x<y:x>y}
                if (a.key==nil) != (b.key==nil) {return a.key != nil}
            }
            if a.title != b.title {return sort == .title && !ascending ? a.title>b.title:a.title<b.title}
            return a.summary.id<b.summary.id
        }.map(\.summary)
    }
}
