import SwiftUI
import MeterCore

@MainActor enum TaskCardMergeUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-card-merge-\(UUID().uuidString)")
        let keys=["CODEX_METER_HOME","CODEX_METER_RENDER_TASK","CODEX_METER_RENDER_SEARCH"],old=keys.map{ProcessInfo.processInfo.environment[$0]}
        for (key,value) in zip(keys,[directory.path,"source","Черновик"]) {setenv(key,value,1)}
        defer {for (key,value) in zip(keys,old) {if let value {setenv(key,value,1)} else {unsetenv(key)}};try? FileManager.default.removeItem(at:directory)}
        var failures=0
        func check(_ ok:Bool,_ name:String){print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle(_ seconds:Double=0.4){let deadline=Date().addingTimeInterval(seconds);while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}}
        func descendants(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap{descendants($0)}}
        do {
            let db=try Database()
            try db.saveTask(WorkTask(id:"source",title:"Черновик документации",kind:""))
            try db.saveTask(WorkTask(id:"target",title:"Подготовить руководство",kind:"",status:"paused"))
            try db.saveRun(RunRecord(id:"run",thread:"thread",started:Date(),tokens:.init(input:123),taskID:"source"))
            try db.bind(thread:"thread",turn:"run",task:"source")
            let store=MeterStore(startServices:false);store.tasks=try db.summaries();store.runs=try db.runs()
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:980,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;defer{window.orderOut(nil)}
            let host=NSHostingView(rootView:TasksView().environmentObject(store).background(MeterTheme.background))
            window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
            check(UIAccessibility.find(host,"task-merge-open") != nil,"Task card exposes merge without expanding a disclosure")
            UIAccessibility.capture(host,"task-card-merge-button")
            UIAccessibility.press(UIAccessibility.find(host,"task-merge-open"));settle()
            guard let first=window.sheets.first?.contentView else {check(false,"Merge button opens a dialog");return false}
            check(!UIAccessibility.enabled(UIAccessibility.find(first,"task-batch-save")),"Card merge cannot save without an explicit destination")
            UIAccessibility.press(UIAccessibility.find(first,"task-batch-cancel"));settle()
            check(try window.sheets.isEmpty && db.tasks().count==2 && db.runs().first?.taskID=="source","Cancelling card merge leaves tasks and runs unchanged")
            UIAccessibility.press(UIAccessibility.find(host,"task-merge-open"));settle()
            guard let dialog=window.sheets.first?.contentView,
                  let search=descendants(dialog).compactMap({$0 as? NSSearchField}).first,
                  let table=descendants(dialog).compactMap({$0 as? NSTableView}).first else {check(false,"Merge dialog provides search and destination list");return false}
            check(table.numberOfRows==1 && UIAccessibility.find(dialog,"task-choice-scope")==nil && UIAccessibility.find(dialog,"task-choice-type")==nil,"Single merge excludes the source and omits extra filters")
            check(search.currentEditor() != nil,"Merge dialog focuses search immediately")
            if let editor=search.currentEditor() as? NSTextView {editor.insertText("руководство",replacementRange:editor.selectedRange())};settle()
            search.currentEditor()?.doCommand(by:#selector(NSResponder.moveDown(_:)));settle()
            check(table.selectedRow==0 && UIAccessibility.enabled(UIAccessibility.find(dialog,"task-batch-save")),"Search and arrow key choose a merge destination")
            UIAccessibility.capture(dialog,"task-card-merge-dialog")
            search.currentEditor()?.doCommand(by:#selector(NSResponder.insertNewline(_:)));settle(1)
            check(try db.tasks().count==1 && db.task("target")?.status=="paused" && db.runs().first?.taskID=="target" && db.summaries().first?.tokens.total==123,"Card merge preserves destination status and transfers runs and tokens")
            check(try db.query("SELECT task_id FROM bindings WHERE thread='thread' AND turn='run'").first?["task_id"]=="target","Card merge transfers the explicit run binding")
            check(window.sheets.isEmpty && UIAccessibility.find(host,"task-merge-open")==nil,"Card merge closes the dialog and cannot merge the only remaining task")
            let title=UIAccessibility.find(host,"task-detail-title").flatMap{UIAccessibility.value($0,"accessibilityValue") as? String}
            check(title=="Подготовить руководство","Card merge reveals the destination despite the source-only search filter")
            UIAccessibility.capture(host,"task-card-merge-result")
            return failures==0
        } catch {print("FAIL task card merge: \(error)");return false}
    }
}
