import SwiftUI
import MeterCore

@MainActor enum TaskTypeUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-types-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer{if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        var failures=0
        func check(_ ok:Bool,_ name:String){print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle(_ seconds:Double=0.4){let deadline=Date().addingTimeInterval(seconds);while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}}
        func descendants(_ v:NSView)->[NSView]{[v]+v.subviews.flatMap{descendants($0)}}
        do {
            let db=try Database(),task=WorkTask(id:"legacy",title:"Обновить руководство",kind:"project-docs")
            try db.saveTask(task)
            check(try db.taskTypes().isEmpty,"Fresh installation has no preset task types")
            try db.saveTaskType(TaskType(id:"documentation",name:"Документация"))
            try db.saveTaskType(TaskType(id:"review",name:"Ревью"))
            let store=MeterStore(startServices:false);store.tasks=try db.summaries()
            check(TaskChoice.matching(TaskChoice.sorted(store.tasks),query:"",scope:0,typeID:"unclassified").count==1,"Chooser type filter identifies unclassified tasks")
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:620,height:720),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;defer{window.orderOut(nil)}
            let host=NSHostingView(rootView:TaskEditor(task:task).environmentObject(store).background(MeterTheme.background))
            window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
            let text=UIAccessibility.nodes(host).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")
            check(text.contains("Нужно указать тип") && text.contains("project-docs"),"Legacy skill is shown as unconfirmed with an explicit classification prompt")
            check(descendants(host).compactMap{$0 as? NSTextField}.filter{$0.isEditable}.count==1,"Task editor allows title entry but offers a picker for type")
            func choose(_ node:NSObject?,_ title:String) {
                guard let node else {check(false,"Type picker exists");return}
                if let popup=node as? NSPopUpButton {popup.menu?.performActionForItem(at:popup.indexOfItem(withTitle:title))}
                else {
                    let observer=NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main){notification in
                        guard let menu=notification.object as? NSMenu else{return}
                        DispatchQueue.main.async {let index=menu.indexOfItem(withTitle:title);if index>=0 {menu.performActionForItem(at:index)};menu.cancelTracking()}
                    }
                    NSApp.activate(ignoringOtherApps:true);UIAccessibility.press(node);settle();NotificationCenter.default.removeObserver(observer)
                }
                settle()
            }
            choose(UIAccessibility.find(host,"task-type-picker"),"Документация")
            UIAccessibility.capture(host,"task-type-selection")
            UIAccessibility.press(UIAccessibility.find(host,"task-editor-save"));settle(1)
            check(try db.task(task.id)?.typeID=="documentation","Task editor saves an explicit catalog ID")
            check(TaskChoice.matching(TaskChoice.sorted(store.tasks),query:"",scope:0,typeID:"documentation").count==1 && TaskChoice.matching(TaskChoice.sorted(store.tasks),query:"",scope:0,typeID:"doc").isEmpty,"Chooser filter matches the exact catalog ID")
            let editor=NSHostingView(rootView:TaskTypeEditor(type:TaskType(id:"documentation",name:"Документация")).environmentObject(store).background(MeterTheme.background))
            window.contentView=editor;settle()
            guard let field=descendants(editor).compactMap({$0 as? NSTextField}).first(where:{$0.placeholderString=="Название типа"}) else{return false}
            func type(_ name:String){field.selectText(nil);if let text=field.currentEditor() as? NSTextView {text.setSelectedRange(NSRange(location:0,length:(text.string as NSString).length));text.insertText(name,replacementRange:text.selectedRange())};settle()}
            type("Ревью");UIAccessibility.press(UIAccessibility.find(editor,"task-type-save"));settle(1)
            check(UIAccessibility.find(editor,"task-type-error") != nil,"Catalog rejects duplicate names in the editor")
            type("Руководства")
            try db.exec("BEGIN IMMEDIATE")
            UIAccessibility.press(UIAccessibility.find(editor,"task-type-save"));settle()
            check(UIAccessibility.find(editor,"action-progress") != nil,"Type editor displays the shared progress overlay during save")
            UIAccessibility.capture(editor,"task-type-saving")
            try db.exec("ROLLBACK");settle(1)
            check(try db.task(task.id)?.typeLabel=="Руководства","Renaming a type updates existing tasks without reclassification")
            let manager=NSHostingView(rootView:TaskTypesManager().environmentObject(store).padding(24).background(MeterTheme.background))
            window.contentView=manager;settle()
            UIAccessibility.press(UIAccessibility.find(manager,"task-type-archive-documentation"));settle(1)
            check(try db.taskTypes().first{$0.id=="documentation"}?.archived==true,"Catalog can archive a type while preserving task links")
            UIAccessibility.capture(manager,"task-type-catalog")
            let deletion=NSHostingView(rootView:TaskTypeDeleteEditor(type:TaskType(id:"documentation",name:"Руководства",archived:true)).environmentObject(store).background(MeterTheme.background))
            window.contentView=deletion;settle()
            UIAccessibility.capture(deletion,"task-type-delete")
            UIAccessibility.press(UIAccessibility.find(deletion,"task-type-delete-confirm"));settle(1)
            check(try db.task(task.id)?.typeID==nil && db.tasks().count==1,"Deleting a type preserves the task and clears classification")
            check(try !db.taskTypes().contains{$0.id=="documentation"},"Deleted type disappears from the shared catalog")
            let browser=NSHostingView(rootView:TasksView().environmentObject(store).background(MeterTheme.background))
            window.setContentSize(NSSize(width:980,height:740));window.contentView=browser;settle()
            check(UIAccessibility.find(browser,"task-types-open") != nil,"Type management is available directly beside task search")
            UIAccessibility.capture(browser,"task-types-entry")
            UIAccessibility.press(UIAccessibility.find(browser,"task-types-open"));settle()
            check(window.sheets.first.flatMap{$0.contentView}.flatMap{UIAccessibility.find($0,"task-type-add")} != nil,"Task browser opens the shared type manager")
            return failures==0
        } catch {print("FAIL task type UI: \(error)");return false}
    }
}
