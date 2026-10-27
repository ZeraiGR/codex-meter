import SwiftUI
import MeterCore

@MainActor enum TaskStatusUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-status-\(UUID().uuidString)")
        let keys=["CODEX_METER_HOME","CODEX_METER_RENDER_TASK"],old=keys.map{ProcessInfo.processInfo.environment[$0]}
        for (key,value) in zip(keys,[directory.path,"status-task"]) {setenv(key,value,1)}
        defer {for (key,value) in zip(keys,old) {if let value {setenv(key,value,1)} else {unsetenv(key)}};try? FileManager.default.removeItem(at:directory)}
        var failures=0
        func check(_ ok:Bool,_ name:String){print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle(_ seconds:Double=0.4){let deadline=Date().addingTimeInterval(seconds);while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}}
        do {
            let db=try Database()
            try db.saveTask(WorkTask(id:"status-task",title:"Дежурство",kind:""))
            let store=MeterStore(startServices:false);store.tasks=try db.summaries()
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
            let host=NSHostingView(rootView:TasksView().textSelection(.enabled).background(MeterTheme.background).actionProgress().environmentObject(store))
            window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
            func find(_ id:String)->NSObject? {
                UIAccessibility.find(host,id) ?? NSApp.windows.filter{$0.isVisible && $0 !== window}.compactMap{window in
                    window.contentView.flatMap{UIAccessibility.find($0,id)}
                }.first
            }
            for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",NSAppearance.Name.darkAqua)] {
                window.appearance=NSAppearance(named:appearance)
                UIAccessibility.press(find("task-complete"));settle(1)
                check(try db.task("status-task")?.status=="completed" && db.task("status-task")?.finished != nil,"Complete button persists status and completion time (\(name))")
                check(UIAccessibility.enabled(find("task-detail-status")),"Completed badge remains an enabled button (\(name))")
                UIAccessibility.capture(host,"task-status-completed-"+name)
                UIAccessibility.press(find("task-detail-status"));settle()
                check(find("task-status-option-ongoing") != nil,"Status badge opens the popup including ongoing tasks")
                if let popup=NSApp.windows.first(where:{$0.isVisible && $0.contentView.map{UIAccessibility.find($0,"task-status-option-ongoing") != nil} ?? false})?.contentView {UIAccessibility.capture(popup,"task-status-popup-"+name)}
                UIAccessibility.press(find("task-status-option-ongoing"));settle(1)
                check(try db.task("status-task")?.status=="ongoing" && db.task("status-task")?.finished==nil,"Ongoing selection reopens explicitly without a completion time")
                check(!TaskChoice(store.tasks[0]).closed && TaskChoice(store.tasks[0]).statusLabel=="Постоянная","Ongoing task stays open and has its own chooser label")
                UIAccessibility.capture(host,"task-status-ongoing-"+name)
                UIAccessibility.press(find("task-detail-status"));settle()
                UIAccessibility.press(find("task-status-option-active"));settle(1)
            }
            try db.exec("CREATE TRIGGER reject_status BEFORE UPDATE ON tasks BEGIN SELECT RAISE(ABORT,'Synthetic status failure'); END")
            UIAccessibility.press(find("task-detail-status"));settle()
            UIAccessibility.press(find("task-status-option-completed"));settle(1)
            check(try db.task("status-task")?.status=="active" && find("task-status-error") != nil,"Failed status change preserves current status and shows retryable popup error")
            check(UIAccessibility.enabled(find("task-status-option-completed")) && !store.isPerformingAction,"Status choices become enabled again after a failed save")
            if let popup=NSApp.windows.first(where:{$0.isVisible && $0.contentView.map{UIAccessibility.find($0,"task-status-error") != nil} ?? false})?.contentView {UIAccessibility.capture(popup,"task-status-error")}
            try db.exec("DROP TRIGGER reject_status")
            UIAccessibility.press(find("task-status-option-completed"));settle(1)
            check(try db.task("status-task")?.status=="completed","Status popup retries successfully")
            return failures==0
        } catch {print("FAIL task status UI: \(error)");return false}
    }
}
