import SwiftUI
import MeterCore

@MainActor enum TaskChooserUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-chooser-\(UUID().uuidString)")
        let oldMeter=ProcessInfo.processInfo.environment["CODEX_METER_HOME"],oldCodex=ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1);setenv("CODEX_HOME",folder.appendingPathComponent("codex").path,1)
        defer {
            if let oldMeter { setenv("CODEX_METER_HOME",oldMeter,1) } else { unsetenv("CODEX_METER_HOME") }
            if let oldCodex { setenv("CODEX_HOME",oldCodex,1) } else { unsetenv("CODEX_HOME") }
            try? FileManager.default.removeItem(at:folder)
        }
        var failures=0
        func check(_ ok:Bool,_ label:String) {print("\(ok ? "PASS":"FAIL") \(label)");if !ok {failures += 1}}
        func settle() {
            let deadline=Date().addingTimeInterval(0.35)
            while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true) {NSApp.sendEvent(event)};NSApp.updateWindows()}
        }
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap{descendants($0)} }
        let now=Date(timeIntervalSince1970:1_789_380_000)
        var tasks=(0..<1200).map { index in
            WorkTask(id:"choice-\(index)",title:"Ревью API заказов: проверка обработки ошибок и совместимости клиентских приложений — выпуск \(index)",kind:"code-review",status:index % 3 == 0 ? "completed":"paused",created:now.addingTimeInterval(-Double(index)*3600))
        }
        tasks[1199].title="Уникальный проект";tasks[1199].kind="Проверка безопасности";tasks[1199].status="completed"
        tasks[1198].title="Уникальный проект";tasks[1198].kind="Ревью интерфейса"
        let run=RunRecord(id:"chooser-run",thread:"chooser",started:now,title:"Проверь обработку ошибок перед выпуском версии")
        do {
            let db=try Database()
            for task in tasks {try db.saveTask(task)}
            try db.saveRun(run)
        } catch {check(false,"Create isolated task chooser fixture: \(error)");return false}
        let store=MeterStore(startServices:false)
        store.tasks=tasks.map { TaskSummary(task:$0,runs:[],quotaPoints:nil,rubles:nil,quotaQuality:"") }
        let choices=TaskChoice.sorted(store.tasks)
        check(choices.count==1200 && choices.first?.id=="choice-0" && TaskChoice.sorted(store.tasks,excluding:"choice-0").count==1199,"Recent tasks sort first and merge excludes the source task")
        check(TaskChoice.matching(choices,query:"  БЕЗОПАСНОСТИ   уникальный ",scope:0).map(\.id)==["choice-1199"],"Task search matches all words across title and type regardless of case")
        check(TaskChoice.matching(choices,query:"Уникальный",scope:1).map(\.id)==["choice-1198"] && TaskChoice.matching(choices,query:"Уникальный",scope:2).map(\.id)==["choice-1199"],"Status filters distinguish open and completed tasks with identical names")
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:620,height:760),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:AssignEditor(run:run).environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        guard let table=descendants(host).compactMap({$0 as? NSTableView}).first,
              let search=descendants(host).compactMap({$0 as? NSSearchField}).first else {
            check(false,"Native task search and virtualized list exist");return false
        }
        func save()->NSObject? {UIAccessibility.find(host,"assignment-save")}
        func type(_ text:String) {
            search.selectText(nil)
            if let editor=search.currentEditor() as? NSTextView {
                editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length));editor.insertText(text,replacementRange:editor.selectedRange())
            };settle()
        }
        func click(_ row:Int) {
            table.scrollRowToVisible(row);settle()
            let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
        }
        check(table.numberOfRows==1200 && table.visibleRect.height>=190 && table.visibleRect.height<=220,"1200 tasks keep a bounded usable list instead of a growing menu")
        check(descendants(table).count<600,"Large task list creates only a bounded number of native views")
        UIAccessibility.capture(host,"task-chooser-many")
        click(1199)
        check(table.selectedRow==1199 && UIAccessibility.enabled(save()),"Scrolling to the last of 1200 tasks supports real mouse selection")
        type("Уникальный")
        check(table.numberOfRows==2 && !UIAccessibility.enabled(save()),"Search finds old tasks and clears a previous assignment before confirmation")
        UIAccessibility.capture(host,"task-chooser-search")
        if let scope=descendants(host).compactMap({$0 as? NSSegmentedControl}).first(where:{$0.segmentCount==3}) {
            scope.selectedSegment=1;scope.sendAction(scope.action,to:scope.target);settle()
            check(table.numberOfRows==1,"Native status control filters the task list")
            scope.selectedSegment=0;scope.sendAction(scope.action,to:scope.target);settle()
        } else {check(false,"Native task status control exists") }
        type("нет такого результата")
        check(table.numberOfRows==0 && !UIAccessibility.enabled(save()) && table.visibleRect.height>=190,"Empty search retains list height and cannot assign a hidden task")
        type("безопасности уникальный")
        search.currentEditor()?.doCommand(by:#selector(NSResponder.moveDown(_:)));settle()
        check(table.numberOfRows==1 && table.selectedRow==0 && UIAccessibility.enabled(save()),"Down arrow from search selects the matching completed task")
        store.updating=true;store.tasks=store.tasks.map{$0};settle()
        check(search.stringValue=="безопасности уникальный" && table.selectedRow==0 && UIAccessibility.enabled(save()),"Background refresh preserves task query and selection")
        UIAccessibility.capture(host,"task-chooser-selected")
        search.currentEditor()?.doCommand(by:#selector(NSResponder.insertNewline(_:)));settle()
        check((try? Database().runs().first{$0.id==run.id}?.taskID)=="choice-1199","Return confirms only the explicitly selected task even with duplicate names")
        return failures==0
    }
}
