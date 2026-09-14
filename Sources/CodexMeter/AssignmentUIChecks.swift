import SwiftUI
import MeterCore

@MainActor enum AssignmentUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-assignment-\(UUID().uuidString)")
        let oldMeter=ProcessInfo.processInfo.environment["CODEX_METER_HOME"],oldCodex=ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1);setenv("CODEX_HOME",folder.appendingPathComponent("codex").path,1)
        defer {
            if let oldMeter {setenv("CODEX_METER_HOME",oldMeter,1)} else {unsetenv("CODEX_METER_HOME")}
            if let oldCodex {setenv("CODEX_HOME",oldCodex,1)} else {unsetenv("CODEX_HOME")}
            try? FileManager.default.removeItem(at:folder)
        }
        let store=MeterStore(startServices:false)
        let run=RunRecord(id:"assign-one",thread:"fixture",started:Date(),ended:Date(),title:"Исправь наложение заголовка при выделении текста",outcome:"completed")
        let second=RunRecord(id:"assign-two",thread:"fixture",started:Date(),ended:Date(),title:"Уточни подписи полей",outcome:"completed")
        do {let db=try Database();try db.saveRun(run);try db.saveRun(second)} catch {print("FAIL Assignment fixture: \(error)");return false}
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:548,height:620),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer {window.orderOut(nil)}
        var host=NSHostingView(rootView:AssignEditor(run:run).environmentObject(store).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=host;window.makeKeyAndOrderFront(nil)
        func settle() {
            let deadline=Date().addingTimeInterval(0.6)
            while Date()<deadline {if let e=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true) {NSApp.sendEvent(e)};NSApp.updateWindows()}
        }
        func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{descendants($0)}}
        func saveButton()->NSObject? {UIAccessibility.find(host,"assignment-save")}
        var failures=0
        func check(_ ok:Bool,_ label:String) {print("\(ok ? "PASS":"FAIL") \(label)");if !ok {failures += 1}}
        settle()
        UIAccessibility.capture(host,"assignment-empty")
        let field=descendants(host).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Какой результат объединяет эти запросы?"}
        check(field != nil && field?.stringValue=="" && UIAccessibility.enabled(saveButton())==false,"New task starts with an empty name and cannot copy the prompt implicitly")
        func typeTitle(_ value:String) {
            field?.selectText(nil)
            if let editor=field?.currentEditor() as? NSTextView {
                editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length));editor.insertText(value,replacementRange:editor.selectedRange())
            };settle()
        }
        typeTitle("   ")
        check(UIAccessibility.enabled(saveButton())==false,"Whitespace is not accepted as a task name")
        typeTitle("Разработка Codex Meter")
        UIAccessibility.capture(host,"assignment-named")
        check(UIAccessibility.enabled(saveButton())==true,"A result name is sufficient without a custom task type")
        UIAccessibility.press(saveButton());settle()
        guard let task=(try? Database().tasks())?.first else {check(false,"Task saved by the dialog");return false}
        let savedRuns=(try? Database().runs()) ?? []
        check(task.title=="Разработка Codex Meter" && task.kind=="Произвольная задача" && task.status=="paused" && task.finished==nil,"Task keeps the result name and remains open after a completed request")
        check(savedRuns.first{$0.id==run.id}?.taskID==task.id && savedRuns.first{$0.id==second.id}?.taskID==nil,"Only the selected request is added to the task")
        // Reassignment must open the existing task, not another prefilled new task.
        var assigned=run;assigned.taskID=task.id
        store.tasks=(try? Database().summaries()) ?? []
        host=NSHostingView(rootView:AssignEditor(run:assigned).environmentObject(store).background(Color(nsColor:.windowBackgroundColor)));window.contentView=host;settle()
        check(!descendants(host).compactMap{$0 as? NSTextField}.contains{$0.placeholderString=="Какой результат объединяет эти запросы?"} && UIAccessibility.enabled(saveButton())==true,"Assigned request opens its existing task without a new task name")
        UIAccessibility.press(saveButton());settle()
        check((try? Database().tasks().count)==1,"Confirming existing assignment does not duplicate the task")
        return failures==0
    }
}
