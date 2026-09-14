import SwiftUI
import MeterCore

@MainActor enum TaskListUIChecks {
    static func run()->Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-task-list-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        let store=MeterStore(startServices:false),now=Date()
        store.tasks=(0..<1200).map { i in
            let task=WorkTask(id:"task-\(i)",title:i==1199 ? "Разработка редактора документов":"Проверка API заказов — выпуск \(i)",kind:i % 2 == 0 ? "Релиз":"Разработка",status:i % 3 == 0 ? "completed":"paused",created:now.addingTimeInterval(-Double(i)*60))
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
              let sort=descendants(host).compactMap({$0 as? NSPopUpButton}).first(where:{$0.itemTitles.contains("Токены")}) else {
            check(false,"Task list and native sorting control exist");return false
        }
        func click(_ row:Int) {
            // Native first-click handling can otherwise consume the click only to
            // activate this fixture after a previous test's popover lost focus.
            NSApp.activate(ignoringOtherApps:true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(table)
            table.scrollRowToVisible(row);settle()
            let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
        }
        sort.menu?.performActionForItem(at:sort.indexOfItem(withTitle:"Токены"));settle();click(0)
        let strings=UIAccessibility.nodes(host).compactMap{UIAccessibility.value($0,"accessibilityValue") as? String}.joined(separator:" ")
        check(table.numberOfRows==1200 && strings.contains("Разработка редактора документов"),"Sorting 1200 tasks by tokens opens the largest task on the first row")
        check(UIAccessibility.find(host,"task-weekly-quota") != nil && UIAccessibility.find(host,"task-quota-partial") != nil,"Selected task shows weekly quota separately with partial coverage")
        UIAccessibility.capture(host,"task-sorting-quota")
        UIAccessibility.press(UIAccessibility.find(host,"task-list-direction"));settle()
        check(table.selectedRow==1199,"Changing sort direction preserves the selected task by ID")
        window.setContentSize(NSSize(width:840,height:620));settle()
        check(table.visibleRect.height>=220,"Sorting controls preserve usable task list height at minimum window size")
        UIAccessibility.press(UIAccessibility.find(host,"task-list-filters"));settle()
        guard let panel=NSApp.windows.first(where:{ w in w.contentView.map{descendants($0).compactMap{$0 as? NSTextField}.contains{$0.placeholderString=="Например: code-review"}} ?? false}),let content=panel.contentView,
              let kind=descendants(content).compactMap({$0 as? NSTextField}).first(where:{$0.placeholderString=="Например: code-review"}) else {
            check(false,"Task filters open in a native popover");return false
        }
        func type(_ value:String) {
            kind.selectText(nil)
            if let editor=kind.currentEditor() as? NSTextView {editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length));editor.insertText(value,replacementRange:editor.selectedRange())};settle()
        }
        type("Релиз")
        if let status=descendants(content).compactMap({$0 as? NSPopUpButton}).first(where:{$0.itemTitles.contains("Все статусы")}) {
            status.menu?.performActionForItem(at:status.indexOfItem(withTitle:"Завершена"));settle()
        }
        check(table.numberOfRows==200,"Status and type filters combine without altering the underlying tasks")
        store.tasks=store.tasks.map{$0};store.updating=true;settle()
        check(table.numberOfRows==200 && sort.titleOfSelectedItem=="Токены","Background refresh preserves task sorting and filters")
        type("такого типа нет")
        check(table.numberOfRows==0 && table.visibleRect.height>=220,"Empty task filter keeps a usable list and a recovery action")
        let done=UIAccessibility.find(content,"task-list-filters-done")
        UIAccessibility.press(done);settle()
        let reset=UIAccessibility.find(host,"task-list-reset")
        UIAccessibility.press(reset);settle()
        check(table.numberOfRows==1200,"Resetting an empty search restores the full task list")

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
