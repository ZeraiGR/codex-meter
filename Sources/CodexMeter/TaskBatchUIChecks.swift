import SwiftUI
import MeterCore

@MainActor enum TaskBatchUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-task-batch-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        do {
            let db=try Database()
            for id in ["one","two","other"] {try db.saveTask(WorkTask(id:id,title:"Задача \(id)",kind:"Разработка"))}
            let store=MeterStore(startServices:false)
            store.tasks=try db.summaries()
            let tasks=store.tasks.filter{$0.id != "other"}
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:568,height:540),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
            var failures=0,saved=false
            func check(_ ok:Bool,_ name:String){print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
            var failed=tasks[0];failed.task.status="failed"
            check(TaskChoice(failed).closed && TaskChoice(failed).statusLabel=="Не удалась","Failed status remains distinct and closed in the merge chooser")
            func settle(_ seconds:Double=0.3){
                let deadline=Date().addingTimeInterval(seconds)
                while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}
            }
            func present(_ kind:TaskBatchKind)->NSView {
                let host=NSHostingView(rootView:TaskBatchEditor(request:TaskBatchRequest(tasks:tasks,kind:kind),onSaved:{_ in saved=true}).environmentObject(store).background(MeterTheme.background))
                window.contentView=host;window.makeKeyAndOrderFront(nil);settle();return host
            }
            let status=present(.status)
            UIAccessibility.press(UIAccessibility.find(status,"task-batch-save"));settle(1)
            check(try saved && (db.task("one")?.status)=="completed" && (db.task("two")?.status)=="completed" && (db.task("other")?.status)=="active","Bulk status dialog saves only the selected tasks")
            saved=false
            let retry=present(.status)
            try db.updateTaskStatuses(["one","two"],status:"active")
            try db.exec("CREATE TRIGGER reject_status BEFORE UPDATE ON tasks WHEN OLD.id='two' BEGIN SELECT RAISE(ABORT,'Synthetic failure'); END")
            UIAccessibility.press(UIAccessibility.find(retry,"task-batch-save"));settle(1)
            check(try !saved && UIAccessibility.find(retry,"task-batch-error") != nil && db.task("one")?.status=="active","Failed bulk status keeps the dialog open and rolls back prior tasks")
            try db.exec("DROP TRIGGER reject_status")
            UIAccessibility.press(UIAccessibility.find(retry,"task-batch-save"));settle(1)
            check(try saved && db.task("one")?.status=="completed" && db.task("two")?.status=="completed","Bulk status can be retried after failure")
            let merge=present(.merge)
            check(!UIAccessibility.enabled(UIAccessibility.find(merge,"task-batch-save")),"Merging requires an explicit destination")
            func descendants(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap{descendants($0)}}
            guard let table=descendants(merge).compactMap({$0 as? NSTableView}).first,
                  let row=TaskChoice.sorted(store.tasks).firstIndex(where:{$0.id=="other"}) else {return false}
            NSApp.activate(ignoringOtherApps:true);settle();window.makeKeyAndOrderFront(nil)
            table.scrollRowToVisible(row);settle()
            let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);window.sendEvent(down);settle()
            check(UIAccessibility.enabled(UIAccessibility.find(merge,"task-batch-save")),"Choosing a destination enables bulk merge")
            UIAccessibility.capture(merge,"task-batch-merge")
            saved=false
            UIAccessibility.press(UIAccessibility.find(merge,"task-batch-save"));settle(1)
            check(try saved && db.tasks().count==1 && db.task("other") != nil,"Bulk merge dialog combines selected tasks into the chosen destination")
            return failures==0
        } catch {print("FAIL task bulk UI fixture: \(error)");return false}
    }
}
