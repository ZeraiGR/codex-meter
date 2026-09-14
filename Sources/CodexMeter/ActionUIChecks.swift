import SwiftUI
import MeterCore

@MainActor enum ActionUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-actions-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:folder)}
        let store=MeterStore(startServices:false)
        let task=WorkTask(title:"Ревью API заказов",kind:"code-review")
        var run=RunRecord(id:"fixture-run",thread:"fixture",started:Date(),ended:Date(),title:"Проверь обработку ошибок",outcome:"completed")
        do {try Database().saveRun(run)} catch {print("FAIL action fixture: \(error)");return false}
        run.taskID=task.id
        store.tasks=[TaskSummary(task:task,runs:[],quotaPoints:nil,rubles:nil,quotaQuality:"Нет измерений")]
        let request=run
        let host=NSHostingView(rootView:AssignEditor(run:request).environmentObject(store))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:620,height:650),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.orderFrontRegardless()
        defer {window.orderOut(nil)}
        func settle(until ready:()->Bool = {false},timeout:Double=0.2) {
            let deadline=Date().addingTimeInterval(timeout)
            repeat {RunLoop.main.run(until:Date().addingTimeInterval(0.01));NSApp.updateWindows()} while !ready() && Date()<deadline
        }
        var failures=0
        func check(_ ok:Bool,_ label:String) {print("\(ok ? "PASS":"FAIL") \(label)");if !ok {failures += 1}}
        let gate=DispatchSemaphore(value:0)
        var result:Result<Void,Error>?
        let accepted=store.performAction("Сохраняем задачу…",operation:{db in
            guard gate.wait(timeout:.now()+10) == .success else {throw MeterError("Test gate timeout")}
            try db.saveTask(task);try db.bind(thread:request.thread,turn:request.id,task:task.id)
        },completion:{result=$0})
        check(accepted && store.isPerformingAction,"Action locks synchronously before asynchronous work starts")
        var duplicateCompleted=false
        store.assign(request,to:WorkTask(title:"Duplicate",kind:"test")) {_ in duplicateCompleted=true}
        settle()
        check(UIAccessibility.find(host,"action-progress") != nil && !UIAccessibility.enabled(UIAccessibility.find(host,"assignment-save")) && !UIAccessibility.enabled(UIAccessibility.find(host,"task-choice-search")),"Assignment shows progress and disables saving and native search while work is pending")
        UIAccessibility.capture(host,"assignment-saving")
        gate.signal();settle(until:{!store.isPerformingAction},timeout:5)
        check(result != nil && !store.isPerformingAction && !duplicateCompleted && store.tasks.count==1 && store.runs.first?.taskID==task.id,"Duplicate action is rejected and UI unlocks with current bindings and statistics")
        var failed=false
        store.performAction("Проверяем откат…",operation:{db in
            try db.savePayment(Payment(amount:100,start:Date(),end:Date().addingTimeInterval(86400*30)))
            try db.saveTask(WorkTask(title:"Must roll back",kind:"test"))
            throw MeterError("Synthetic failure after nested payment transaction")
        },completion:{if case .failure=$0 {failed=true}})
        settle(until:{!store.isPerformingAction},timeout:5)
        check(failed && !store.isPerformingAction && (try? Database().payments().isEmpty)==true && (try? Database().tasks().count)==1,"Failure rolls back nested writes and releases the action gate")
        var retried=false
        store.saveTask(task) {if case .success=$0 {retried=true}}
        settle(until:{!store.isPerformingAction},timeout:5)
        check(retried && store.tasks.count==1,"Saving can be retried after a failure without a duplicate task")
        store.updating=true;settle()
        check(UIAccessibility.find(host,"action-progress")==nil,"Background quota polling does not block editing")
        return failures==0
    }
}
