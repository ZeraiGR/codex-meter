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
        guard let table=tables.first else {check(false,"Native run list exists");return false}
        check(table.visibleRect.height>=220,"Unselected run list occupies usable height")
        check((1..<table.numberOfRows).allSatisfy{table.rect(ofRow:$0).height>=100},"Long titles and metadata have separate row space")
        let search=descendants(host).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Поиск по запросам и ответам"}
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
        return failures==0
    }
}
