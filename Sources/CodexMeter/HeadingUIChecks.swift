import SwiftUI
import MeterCore

@MainActor enum HeadingUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-heading-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:folder)}
        let store=MeterStore(startServices:false)
        let title=String(("[Изображение] Длинный запрос: проверьте обработку ошибок API, объясните причины сбоев и предложите исправления для следующего релиза. "+"Нужны подробные рекомендации по валидации запросов, совместимости клиентов и интеграционным проверкам.").prefix(180))
        let run=RunRecord(id:"heading",thread:"fixture",started:Date(),title:title)
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:440,height:600),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:RunDetailView(run:run,assign:{}).environmentObject(store).background(Color(nsColor:.windowBackgroundColor)))
        host.sizingOptions=[]
        window.contentView=host;host.frame=NSRect(x:0,y:0,width:440,height:600);window.makeKeyAndOrderFront(nil)
        func settle() {
            let deadline=Date().addingTimeInterval(0.4)
            while Date()<deadline {if let e=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true) {NSApp.sendEvent(e)};NSApp.updateWindows()}
        }
        func element(_ id:String)->NSObject? {UIAccessibility.find(host,id)}
        var failures=0
        func check(_ value:Bool,_ label:String) {print("\(value ? "PASS":"FAIL") \(label)");if !value {failures += 1}}
        settle()
        UIAccessibility.capture(host,"heading-before")
        guard let heading=element("run-heading-title"),let subtitle=element("run-heading-subtitle") else {print("FAIL Title accessibility elements missing: \(UIAccessibility.nodes(host).map{String(describing:type(of:$0))+":"+String(describing:UIAccessibility.value($0,"accessibilityIdentifier"))})");return false}
        for width in [440.0,640.0] {
            window.setContentSize(NSSize(width:width,height:600));host.frame=NSRect(x:0,y:0,width:width,height:600);settle()
            let before=UIAccessibility.frame(heading),dateBefore=UIAccessibility.frame(subtitle)
            check(before.minY>=dateBefore.maxY,"Full title stays above metadata at width \(Int(width))")
            let location=window.convertPoint(fromScreen:NSPoint(x:before.minX+70,y:before.maxY-10))
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:location,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:2,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:location,modifierFlags:[],timestamp:0.1,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:2,pressure:0)!
            NSApp.postEvent(up,atStart:true);NSApp.sendEvent(down);settle()
            let editor=window.firstResponder as? NSTextView
            check(editor?.selectedRange().length ?? 0 > 0,"Double click selects title text at width \(Int(width))")
            if let editor {
                editor.selectAll(nil)
                check(editor.string==title,"Selection contains the complete heading at width \(Int(width))")
                editor.layoutManager?.ensureLayout(for:editor.textContainer!)
                let used=editor.layoutManager?.usedRect(for:editor.textContainer!) ?? .zero
                let editorFrame=window.convertToScreen(editor.convert(editor.bounds,to:nil))
                check(used.height<=editor.bounds.height+1 && editorFrame.minY>=UIAccessibility.frame(subtitle).maxY-1,"Selected title fits its own area without covering the date at width \(Int(width))")
            } else {check(false,"Selectable title has a native editor")}
            check(UIAccessibility.frame(heading)==before && UIAccessibility.frame(subtitle)==dateBefore,"Selecting heading does not move metadata at width \(Int(width))")
            UIAccessibility.capture(host,"heading-selected-\(Int(width))")
            window.makeFirstResponder(nil);settle()
        }
        return failures==0
    }
}
