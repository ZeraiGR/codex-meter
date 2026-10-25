import AppKit
import SwiftUI
import MeterCore

@MainActor enum ExecutionUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-execution-ui-"+UUID().uuidString)
        let keys=["CODEX_METER_HOME","CODEX_METER_RENDER_TASK"],old=keys.map{ProcessInfo.processInfo.environment[$0]}
        setenv(keys[0],directory.path,1);setenv(keys[1],"context-task",1)
        defer {for (key,value) in zip(keys,old) {if let value {setenv(key,value,1)} else {unsetenv(key)}};try? FileManager.default.removeItem(at:directory)}
        let store=MeterStore(startServices:false),now=Date()
        var run=RunRecord(id:"context-run",thread:"context-thread",started:now.addingTimeInterval(-300),ended:now,tokens:.init(input:120000,cached:90000,output:8000,reasoning:5000),model:"example-model-2026-10-01",effort:"high",title:"Проверить поиск документов",taskID:"context-task")
        run.execution=ExecutionContext(originator:"codex-tui",clientVersion:"0.example",source:"cli")
        run.execution?.record(ExecutionConfiguration(model:run.model,effort:run.effort,provider:"openai",serviceTier:"priority",contextWindow:200000))
        run.execution?.add(run.tokens)
        run.execution?.record(ExecutionToolCall(id:"call-one",name:"search",server:"documentation",status:"completed",completedAt:now,duration:1.5))
        run.execution?.record(ExecutionToolCall(id:"call-two",name:"fetch",server:"documentation",status:"failed",completedAt:now,duration:0.3))
        store.runs=[run]
        store.tasks=[TaskSummary(task:WorkTask(id:"context-task",title:"Поиск по внутренней документации",kind:"Разработка"),runs:[run],quotaPoints:nil,rubles:nil,quotaQuality:"Измерена часть задачи",measuredRubles:126,costCoverage:0.5,weeklyQuota:WeeklyQuotaUsage(points:1.4,coverage:0.5,windowCount:1))]
        var failures=0
        func check(_ value:Bool,_ name:String) {print("\(value ? "PASS":"FAIL") \(name)");if !value {failures += 1}}
        func settle() {let until=Date().addingTimeInterval(0.5);while Date()<until {if let event=NSApp.nextEvent(matching:.any,until:until,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}}
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:980,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer{window.orderOut(nil)}
        let host=NSHostingView(rootView:DashboardView().environmentObject(store))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        func text()->String {UIAccessibility.nodes(host).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")}
        check(UIAccessibility.find(host,"task-expense-details") != nil && !text().contains("Измерения покрывают") && !text().contains("Из него reasoning"),"Task overview keeps expense details collapsed")
        check(!text().contains("Следующая похожая задача") && text().contains(run.model) && text().contains("high"),"Task overview shows model and effort without the next-task forecast")
        UIAccessibility.capture(host,"task-overview-context-light")
        host.appearance=NSAppearance(named:.darkAqua);settle();UIAccessibility.capture(host,"task-overview-context-dark")
        host.appearance=nil;settle()
        UIAccessibility.toggleDisclosure(UIAccessibility.find(host,"task-expense-details"),in:window);settle()
        UIAccessibility.capture(host,"task-expense-expanded")
        let scroll=UIAccessibility.nodes(host).compactMap{$0 as? NSScrollView}.last
        if let scroll,let document=scroll.documentView {document.scroll(NSPoint(x:0,y:max(0,document.bounds.height-scroll.contentSize.height)));scroll.reflectScrolledClipView(scroll.contentView);settle()}
        check(text().contains("Из него reasoning") && text().contains(Format.tokens(run.tokens.cached)),"Expense disclosure reveals the retained token breakdown")
        UIAccessibility.capture(host,"task-expense-breakdown")
        scroll?.documentView?.scroll(.zero);settle()
        window.setContentSize(NSSize(width:840,height:620));settle();UIAccessibility.capture(host,"task-overview-context-compact")
        let details=NSHostingView(rootView:ScrollView{ExecutionContextView(run:run).padding(24)}.frame(width:580,height:560).background(MeterTheme.background))
        window.setContentSize(NSSize(width:580,height:560));window.contentView=details;settle()
        let values=UIAccessibility.nodes(details).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")
        check(values.contains("codex-tui") && values.contains("documentation / search") && values.contains("documentation / fetch"),"Execution context exposes recorded harness and actual MCP tools")
        check(values.contains("полный список") && values.contains("не раскрывается"),"Missing inventory and exact model revision remain explicit")
        UIAccessibility.capture(details,"run-execution-context")
        return failures==0
    }
}
