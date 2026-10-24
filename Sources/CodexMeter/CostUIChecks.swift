import SwiftUI
import MeterCore

@MainActor enum CostUIChecks {
    static func run()->Bool {
        let task=WorkTask(title:"Разработка приложения",kind:"Разработка",status:"paused")
        let run=RunRecord(id:"cost",thread:"test",started:Date(),ended:Date(),tokens:.init(input:200))
        let examples:[(String,Double?,Double?,Double?)]=[("complete",60,60,1),("partial",nil,30,0.5),("unknown",nil,nil,nil)]
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:400,height:470),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer{window.orderOut(nil)}
        var failures=0
        func check(_ ok:Bool,_ label:String){print("\(ok ? "PASS":"FAIL") \(label)");if !ok{failures += 1}}
        for hasRate in [false,true] {
        let rate:USDExchangeRate?=hasRate ? USDExchangeRate(rublesPerDollar:80,effectiveDate:Date().addingTimeInterval(-86400),fetchedAt:Date()):nil
        for (name,total,measured,coverage) in examples {
            let s=TaskSummary(task:task,runs:[run],quotaPoints:nil,rubles:total,quotaQuality:"",measuredRubles:measured,costCoverage:coverage)
            let host=NSHostingView(rootView:VStack{Card{TaskCostView(summary:s,exchangeRate:rate,exchangeRateIssue:hasRate ? "Не удалось обновить курс USD.":nil)};Spacer()}.padding(20).background(Color(nsColor:.windowBackgroundColor)))
            host.sizingOptions=[];window.contentView=host;host.frame=NSRect(x:0,y:0,width:400,height:470);window.makeKeyAndOrderFront(nil)
            let deadline=Date().addingTimeInterval(0.4)
            while Date()<deadline {if let e=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(e)};NSApp.updateWindows()}
            let amount=UIAccessibility.find(host,"task-cost-amount"),incomplete=UIAccessibility.find(host,"task-cost-incomplete")
            if let expected=total ?? measured {
                check(amount != nil && UIAccessibility.value(amount!,"accessibilityValue") as? String=="≈ "+Format.rub(expected),"Task cost shows the summed ruble amount: \(name)")
                check((incomplete != nil)==(total==nil),"Partial cost is distinguished from the complete sum: \(name)")
                if let amount {let rect=UIAccessibility.frame(amount);check(rect.width>0 && rect.width<400,"Ruble amount fits the task card: \(name)")}
            } else {check(amount==nil,"Missing measurements do not render a zero ruble price")}
            let dollars=UIAccessibility.find(host,"task-cost-amount-usd")
            if let expected=rate?.dollars(for:total ?? measured) {
                check(dollars != nil && UIAccessibility.value(dollars!,"accessibilityValue") as? String=="≈ "+Format.usd(expected),"USD uses the same measured amount and the saved rate: \(name)")
                if let dollars,let amount {check(!UIAccessibility.frame(dollars).intersects(UIAccessibility.frame(amount)),"RUB and USD do not overlap")}
            } else {check(dollars==nil,"No fabricated USD without rate or cost: \(name)")}
            let dollarProjection=UIAccessibility.find(host,"task-cost-projection-usd")
            if let expected=rate?.dollars(for:s.projectedRubles) {
                check(dollarProjection != nil && UIAccessibility.value(dollarProjection!,"accessibilityValue") as? String=="≈ "+Format.usd(expected),"USD projection remains separate from measured cost")
            } else {check(dollarProjection==nil,"No USD projection without rate or projected cost")}
            let projected=UIAccessibility.find(host,"task-cost-projection")
            if let expected=s.projectedRubles {
                check(projected != nil && UIAccessibility.value(projected!,"accessibilityValue") as? String=="≈ "+Format.rub(expected),"Projected total is displayed separately from measured cost")
                if let projected,let amount {
                    let a=UIAccessibility.frame(amount),b=UIAccessibility.frame(projected)
                    check(!a.intersects(b) && a.width>0 && b.width>0,"Measured and projected amounts do not overlap in a narrow card")
                } else {check(false,"Both cost columns exist")}
            } else {check(projected==nil,"Projection is absent when full cost exists or measurements are missing: \(name)")}
            UIAccessibility.capture(host,"task-cost-"+name+(hasRate ? "-usd":""))
        }
        }
        return failures==0
    }
}
