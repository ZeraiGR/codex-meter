import SwiftUI
import MeterCore

/// Exercise the native list before a selection exists, where intrinsic sizing
/// previously collapsed the sidebar. Uses isolated synthetic history only.
@MainActor enum BrowserUIChecks {
    static func run() -> Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-ui-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        let store=MeterStore(startServices:false)
        var runs:[RunRecord]=[]
        let journal=directory.appendingPathComponent("conversation.jsonl")
        var events:[[String:Any]]=[]
        func event(_ type:String,_ payload:[String:Any]) {events.append(["type":type,"timestamp":"2026-09-13T12:00:00Z","payload":payload])}
        for i in 1...3 {
            var run=RunRecord(id:"ui-\(i)",thread:"ui",started:Date(),ended:Date(),title:"Ревью API заказов: подробная проверка обработки ошибок, валидации входных данных и совместимости с клиентскими приложениями — пример \(i)")
            run.sourcePath=journal.path;run.category="conversation";run.preview="Ответ Codex с конкретными рекомендациями по улучшению API.";runs.append(run)
            event("event_msg",["type":"task_started","turn_id":run.id])
            event("response_item",["type":"message","role":"user","content":[["type":"input_text","text":run.title]]])
            event("response_item",["type":"message","role":"assistant","phase":"final_answer","content":[["type":"output_text","text":"Уникальныйответ: рекомендации по коду."]]])
            event("event_msg",["type":"task_complete","turn_id":run.id])
        }
        let lines=events.compactMap{try? JSONSerialization.data(withJSONObject:$0)}.map{String(decoding:$0,as:UTF8.self)}.joined(separator:"\n")+"\n"
        try? lines.write(to:journal,atomically:true,encoding:.utf8)
        store.runs=runs
        var failures=0
        func check(_ ok:Bool,_ name:String) {print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle(_ seconds:Double=0.5) {
            let deadline=Date().addingTimeInterval(seconds)
            while Date()<deadline {
                if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true) {NSApp.sendEvent(event)}
                NSApp.updateWindows()
            }
        }
        func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{descendants($0)}}
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:980,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:DashboardView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        let tables=descendants(host).compactMap{$0 as? NSTableView}
        guard tables.first != nil else {check(false,"Native run list exists");return false}
        var table:NSTableView {descendants(host).compactMap{$0 as? NSTableView}.first!}
        check(table.visibleRect.height>=220,"Unselected run list occupies usable height")
        check((1..<table.numberOfRows).allSatisfy{table.rect(ofRow:$0).height>=100},"Long titles and metadata have separate row space")
        var search:NSTextField? {descendants(host).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Поиск по запросам и ответам"}}
        func typeQuery(_ value:String) {
            search?.selectText(nil)
            if let editor=search?.currentEditor() as? NSTextView {
                editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length));editor.insertText(value,replacementRange:editor.selectedRange())
            }
            settle(1)
        }
        typeQuery("уникальныйответ")
        check(table.numberOfRows==4 && table.visibleRect.height>=220,"Typing a query finds three full-text matches before any selection")
        // Native selection through mouse events, not an injected SwiftUI state.
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        settle()
        let row=(0..<table.numberOfRows).first{table.rect(ofRow:$0).height>40} ?? 1
        let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
        let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
        NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
        check(table.selectedRow==row,"Mouse click selects a run")
        check(descendants(host).compactMap{$0 as? NSTextField}.contains{$0.placeholderString=="Найти в сообщениях"},"Click opens the conversation controls")
        // A deleted journal makes any accidental background re-search lose these
        // answer-only matches. Existing results must remain until explicit refresh.
        try? FileManager.default.removeItem(at:journal)
        var service=RunRecord(id:"service",thread:"service",started:Date());service.category="service"
        store.runs.append(service);store.updating=true;settle(1)
        check(table.numberOfRows==4 && table.selectedRow==row,"New service run and quota refresh preserve search results and selection")
        store.runs=runs;store.updating=false;settle(1)
        check(table.numberOfRows==4 && table.selectedRow==row,"Repeated history publication does not restart full-text search")
        window.setContentSize(NSSize(width:840,height:620));settle()
        check(table.visibleRect.height>=220,"Run list stays usable at minimum window size")
        typeQuery("неттакойфразы")
        check(table.numberOfRows==0 && table.visibleRect.height>=220,"No matches keeps a full-height list")
        typeQuery("")
        check(table.numberOfRows==4 && table.visibleRect.height>=220,"Clearing search restores clickable rows")
        func clickRow(_ row:Int,_ flags:NSEvent.ModifierFlags=[]) {
            NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(table)
            table.scrollRowToVisible(row);settle()
            let point=table.convert(NSPoint(x:table.bounds.midX,y:table.rect(ofRow:row).midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:flags,timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
        }
        func clickControl(_ id:String) {
            guard let control=UIAccessibility.find(host,id) else {check(false,"Visible control exists: "+id);return}
            NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
            let frame=UIAccessibility.frame(control)
            let point=window.convertPoint(fromScreen:NSPoint(x:frame.midX,y:frame.midY))
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
        }
        func assignmentCount()->String? {
            clickControl("run-assign-selected")
            guard let content=window.attachedSheet?.contentView else {return nil}
            let count=UIAccessibility.find(content,"assignment-selection-count")
                .flatMap{UIAccessibility.value($0,"accessibilityValue") as? String}
            UIAccessibility.press(UIAccessibility.find(content,"assignment-cancel"));settle()
            return count
        }
        func key(_ text:String,_ code:UInt16,_ flags:NSEvent.ModifierFlags=[]) {
            window.makeFirstResponder(table)
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
            if !window.performKeyEquivalent(with:event) {NSApp.sendEvent(event)};settle()
        }
        check(UIAccessibility.find(host,"run-selection-mode")==nil,"Selection needs no separate mode button")
        // Reproduce the reported loss: nine checks, then a miss beside the tenth.
        store.runs=runs+(4...10).map {RunRecord(id:"ui-\($0)",thread:"ui",started:runs[0].started,title:"Дополнительный запуск \($0)")};settle()
        func checkbox(_ index:Int) {
            table.scrollRowToVisible(index);settle()
            clickControl("run-check-ui-\(index)")
        }
        for index in 1...9 {checkbox(index)}
        check(assignmentCount()=="Выбрано запусков: 9","Nine independently checked runs reach assignment")
        table.scrollRowToVisible(10);settle()
        if let control=UIAccessibility.find(host,"run-check-ui-10") {
            let frame=UIAccessibility.frame(control)
            let point=window.convertPoint(fromScreen:NSPoint(x:frame.maxX+4,y:frame.midY))
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
            check(frame.width>=44 && frame.height>=44,"Checkbox target is at least 44 by 44 points")
        } else {check(false,"Tenth checkbox exists")}
        check(assignmentCount()=="Выбрано запусков: 9","Missing the tenth checkbox preserves all nine checks")
        clickRow(10)
        check(assignmentCount()=="Выбрано запусков: 9","Opening an unchecked transcript preserves the checked batch")
        check(descendants(host).compactMap{$0 as? NSTextField}.contains{$0.placeholderString=="Найти в сообщениях"},"Transcript remains readable while a batch is checked")
        checkbox(10)
        check(assignmentCount()=="Выбрано запусков: 10","The tenth checkbox adds one run without replacing the nine")
        UIAccessibility.capture(host,"run-checks-preview")
        clickRow(2);clickRow(0);key(String(UnicodeScalar(NSDownArrowFunctionKey)!),125)
        check(assignmentCount()=="Выбрано запусков: 10","Card clicks, header clicks and arrow navigation preserve all checks")
        key("\u{1b}",53)
        check(assignmentCount()=="Выбрано запусков: 10","Escape does not discard accumulated checks")
        checkbox(4)
        check(assignmentCount()=="Выбрано запусков: 9","Unchecking one run removes only that run")
        checkbox(4)
        let idleHeight=table.visibleRect.height
        UIAccessibility.capture(host,"run-bulk-selection")
        window.setContentSize(NSSize(width:980,height:740));table.scrollRowToVisible(1);settle()
        UIAccessibility.capture(host,"run-bulk-selection-wide")
        host.appearance=NSAppearance(named:.darkAqua);settle()
        UIAccessibility.capture(host,"run-bulk-selection-dark")
        host.appearance=nil;window.setContentSize(NSSize(width:840,height:620));settle()
        clickControl("run-clear-selection")
        check(UIAccessibility.find(host,"run-assign-selected")==nil,"Explicit clear removes the batch")
        check(abs(table.visibleRect.height-idleHeight)<1,"Clearing checks does not move or shrink the list")
        store.runs=runs;settle()
        clickRow(1)
        check(UIAccessibility.find(host,"run-assign-selected")==nil,"Opening a transcript does not silently check it")
        checkbox(1);checkbox(3)
        check(assignmentCount()=="Выбрано запусков: 2","Checkboxes select nonadjacent runs and cancel keeps the batch")
        clickControl("run-select-visible")
        check(assignmentCount()=="Выбрано запусков: 3","Select shown adds all three runs")
        store.runs=runs;settle()
        check(assignmentCount()=="Выбрано запусков: 3","History refresh preserves the checked run IDs")
        typeQuery("неттакойфразы")
        check(UIAccessibility.find(host,"run-assign-selected")==nil,"Filtering out checked runs excludes them from assignment")
        typeQuery("")
        check(UIAccessibility.find(host,"run-assign-selected")==nil,"Clearing a filter does not silently recheck hidden runs")
        clickControl("run-select-visible");typeQuery("пример 1")
        check(assignmentCount()=="Выбранный запрос","Search keeps only matching checked IDs")
        search?.selectText(nil);NSApp.sendAction(#selector(NSText.selectAll(_:)),to:nil,from:nil);settle()
        check((search?.currentEditor() as? NSTextView)?.selectedRange().length==8,"Select All in search selects text independently of checks")
        typeQuery("");clickControl("run-clear-selection")
        store.runs=runs+(4...105).map {RunRecord(id:"ui-\($0)",thread:"ui",started:runs[0].started,title:"Дополнительный запуск \($0)")};settle()
        clickControl("run-select-visible")
        check(assignmentCount()=="Выбрано запусков: 100","Select shown assigns only 100 loaded runs out of 105")
        clickControl("run-select-visible")
        check(UIAccessibility.find(host,"run-assign-selected")==nil,"Select shown can explicitly uncheck all loaded runs")
        return failures==0
    }
}
