import SwiftUI
import MeterCore

@MainActor enum TaskListUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-task-list-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        let store=MeterStore(startServices:false),now=Date()
        store.taskTypes=[TaskType(id:"release",name:"Релиз"),TaskType(id:"development",name:"Разработка")]
        store.tasks=(0..<1200).map { i in
            var task=WorkTask(id:"task-\(i)",title:i==1199 ? "Разработка редактора документов":"Проверка API заказов — выпуск \(i)",kind:i % 2 == 0 ? "Релиз":"Разработка",status:i % 3 == 0 ? "completed":"paused",created:now.addingTimeInterval(-Double(i)*60))
            task.typeID=i % 2 == 0 ? "release":"development"
            let run=RunRecord(id:task.id,thread:task.id,started:task.created,ended:task.created.addingTimeInterval(20),tokens:.init(input:Int64((i+1)*10000)),taskID:task.id)
            return TaskSummary(task:task,runs:[run],quotaPoints:nil,rubles:nil,quotaQuality:"Измерено 50% токенов задачи",measuredRubles:126,costCoverage:0.5,weeklyQuota:WeeklyQuotaUsage(points:8.4,coverage:0.5,windowCount:1))
        }
        var failures=0
        func check(_ ok:Bool,_ name:String) {print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle() {
            let deadline=Date().addingTimeInterval(0.45)
            while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}
        }
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap{descendants($0)} }
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:980,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:DashboardView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU"))).withBackground()
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        UIAccessibility.capture(host,"task-empty-wide")
        window.setContentSize(NSSize(width:840,height:620));settle()
        UIAccessibility.capture(host,"task-empty-compact")
        window.setContentSize(NSSize(width:980,height:740));settle()
        guard let table=descendants(host).compactMap({$0 as? NSTableView}).first,
              let sort=UIAccessibility.find(host,"task-list-sort") else {
            check(false,"Task list and native sorting control exist");return false
        }
        func choose(_ popup:NSObject?,_ title:String) {
            guard let popup else {check(false,"Menu control exists: "+title);return}
            if let native=popup as? NSPopUpButton {
                native.menu?.performActionForItem(at:native.indexOfItem(withTitle:title))
            } else {
                // Newer SwiftUI exposes the picker through accessibility and a tracked menu.
                let observer=NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main) { notification in
                    guard let menu=notification.object as? NSMenu else {return}
                    DispatchQueue.main.async {
                        let index=menu.indexOfItem(withTitle:title)
                        if index>=0 {menu.performActionForItem(at:index)}
                        menu.cancelTracking()
                    }
                }
                defer {NotificationCenter.default.removeObserver(observer)}
                NSApp.activate(ignoringOtherApps:true)
                UIAccessibility.press(popup)
                settle()
            }
            settle()
        }
        func click(_ row:Int) {
            // Native first-click handling can otherwise consume the click only to
            // activate this fixture after a previous test's popover lost focus.
            NSApp.activate(ignoringOtherApps:true);settle()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(table)
            table.scrollRowToVisible(row);settle()
            let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);window.sendEvent(down);settle()
        }
        choose(sort,"Токены");click(0)
        let strings=UIAccessibility.nodes(host).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")
        check(table.numberOfRows==1200 && strings.contains("Разработка редактора документов"),"Sorting 1200 tasks by tokens opens the largest task on the first row")
        check(!strings.contains("Измерения покрывают"),"Task expense breakdown starts collapsed")
        func selectedCount()->String {UIAccessibility.find(host,"task-selection-count").flatMap{UIAccessibility.value($0,"accessibilityValue") as? String} ?? ""}
        check(UIAccessibility.find(host,"task-check-task-1199")==nil && UIAccessibility.find(host,"task-selection-count")==nil,"Task checkboxes and mass actions start hidden")
        check(UIAccessibility.find(host,"task-unclassified-filter")==nil,"No unclassified shortcut is shown when every task has a type")
        UIAccessibility.press(UIAccessibility.find(host,"selection-mode-toggle"));settle()
        UIAccessibility.press(UIAccessibility.find(host,"task-check-task-1199"));settle()
        check(selectedCount()=="Выбрано: 1","Icon enables task selection")
        UIAccessibility.press(UIAccessibility.find(host,"selection-mode-toggle"));settle()
        check(UIAccessibility.find(host,"task-check-task-1199")==nil && UIAccessibility.find(host,"task-selection-count")==nil && table.selectedRow==0,"Disabling selection hides checks and preserves the open card")
        UIAccessibility.press(UIAccessibility.find(host,"selection-mode-toggle"));settle()
        check(selectedCount()=="Выбрано: 0","Re-enabling selection starts without stale checks")
        for row in 0..<9 {
            table.scrollRowToVisible(row);settle()
            UIAccessibility.press(UIAccessibility.find(host,"task-check-task-\(1199-row)"));settle()
        }
        check(selectedCount()=="Выбрано: 9","Nine task checks accumulate independently")
        click(9)
        check(selectedCount()=="Выбрано: 9","Opening a tenth task preserves nine checks")
        UIAccessibility.press(UIAccessibility.find(host,"task-check-task-1190"));settle()
        check(selectedCount()=="Выбрано: 10","Tenth task checkbox extends the accumulated selection")
        UIAccessibility.capture(host,"task-multiple-selection-light")
        window.appearance=NSAppearance(named:.darkAqua);settle()
        UIAccessibility.capture(host,"task-multiple-selection-dark")
        window.appearance=NSAppearance(named:.aqua);click(0)

        UIAccessibility.capture(host,"task-overview-simple")
        UIAccessibility.toggleDisclosure(UIAccessibility.find(host,"task-expense-details"),in:window);settle()
        let details=UIAccessibility.nodes(host).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")
        check(details.contains("≈ 8,4%") && details.contains("Измерения покрывают 50%"),"Selected task shows weekly quota separately with partial coverage")
        UIAccessibility.capture(host,"task-sorting-quota")
        UIAccessibility.press(UIAccessibility.find(host,"task-list-direction"));settle()
        check(selectedCount()=="Выбрано: 10","Sorting keeps task checks by identity")
        check(table.selectedRow==1199,"Changing sort direction preserves the selected task by ID")
        window.setContentSize(NSSize(width:840,height:620));settle()
        check(table.visibleRect.height>=220,"Sorting controls preserve usable task list height at minimum window size")
        UIAccessibility.press(UIAccessibility.find(host,"task-list-filters"));settle()
        guard let panel=NSApp.windows.first(where:{$0.contentView.map{UIAccessibility.find($0,"task-list-kind") != nil} ?? false}),let content=panel.contentView else {
            check(false,"Task filters open in a native popover");return false
        }
        choose(UIAccessibility.find(content,"task-list-kind"),"Релиз")
        choose(UIAccessibility.find(content,"task-list-status"),"Завершена")
        check(table.numberOfRows==200,"Status and type filters combine without altering the underlying tasks")
        store.tasks=store.tasks.map{$0};store.updating=true;settle()
        check(table.numberOfRows==200 && ((sort as? NSPopUpButton)?.titleOfSelectedItem ?? UIAccessibility.value(sort,"accessibilityValue") as? String)=="Токены","Background refresh preserves task sorting and filters")
        choose(UIAccessibility.find(content,"task-list-kind"),"Тип не указан")
        check(selectedCount()=="Выбрано: 0","Filtering out tasks excludes them from mass actions")
        check(table.numberOfRows==0 && table.visibleRect.height>=220,"Empty task filter keeps a usable list and a recovery action")
        let done=UIAccessibility.find(content,"task-list-filters-done")
        UIAccessibility.press(done);settle()
        let reset=UIAccessibility.find(host,"task-list-reset")
        UIAccessibility.press(reset);settle()
        check(table.numberOfRows==1200,"Resetting an empty search restores the full task list")

        UIAccessibility.press(UIAccessibility.find(host,"selection-mode-toggle"));settle()
        store.tasks[0].task.typeID=nil;store.tasks[1].task.typeID=nil;settle()
        let search=descendants(host).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Поиск задачи или типа"}
        search?.selectText(nil)
        if let editor=search?.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length));editor.insertText("неттакойзадачи",replacementRange:editor.selectedRange())
        }
        settle();check(table.numberOfRows==0,"Existing search can hide unclassified tasks")
        UIAccessibility.press(UIAccessibility.find(host,"task-unclassified-filter"));settle()
        check(table.numberOfRows==2 && UIAccessibility.find(host,"task-unclassified-badge-task-0") != nil,"One click finds and highlights tasks without a type")
        UIAccessibility.capture(host,"task-unclassified-light")
        window.appearance=NSAppearance(named:.darkAqua);settle()
        UIAccessibility.capture(host,"task-unclassified-dark")
        window.appearance=NSAppearance(named:.aqua)
        store.tasks=store.tasks.map{$0};store.updating=true;settle()
        check(table.numberOfRows==2,"Background refresh preserves the unclassified shortcut filter")
        UIAccessibility.press(UIAccessibility.find(host,"selection-mode-toggle"));settle()
        UIAccessibility.press(UIAccessibility.find(host,"task-select-visible"));settle()
        check(selectedCount()=="Выбрано: 2","Unclassified tasks can be selected together for classification")
        check(table.visibleRect.height>=220,"Unclassified filter and selection mode preserve usable list height")
        UIAccessibility.capture(host,"task-unclassified-selection")
        store.tasks[0].task.typeID="release";store.tasks[1].task.typeID="development";settle()
        check(table.numberOfRows==0 && selectedCount()=="Выбрано: 0" && UIAccessibility.find(host,"task-unclassified-filter") != nil,"Classified tasks leave the selection while the empty shortcut can still be switched off")
        UIAccessibility.press(UIAccessibility.find(host,"task-unclassified-filter"));settle()
        check(table.numberOfRows==1200 && UIAccessibility.find(host,"task-unclassified-filter")==nil,"Switching off the empty shortcut restores all tasks")

        var summary=store.tasks[0]
        summary.weeklyQuota=WeeklyQuotaUsage(points:150,coverage:1,windowCount:2)
        let quotaHost=NSHostingView(rootView:Card{TaskQuotaView(summary:summary)}.padding(18).frame(width:400).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=quotaHost;settle()
        let total=UIAccessibility.find(quotaHost,"task-weekly-quota")
        check(total.flatMap{UIAccessibility.value($0,"accessibilityValue") as? String}=="≈ 150%" && UIAccessibility.find(quotaHost,"task-quota-periods") != nil,"Multi-week task shows total above 100 percent with its period explanation")
        UIAccessibility.capture(quotaHost,"task-quota-multiple-weeks")
        return failures==0
    }
}

private extension NSHostingView {
    func withBackground()->Self {wantsLayer=true;layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor;return self}
}
