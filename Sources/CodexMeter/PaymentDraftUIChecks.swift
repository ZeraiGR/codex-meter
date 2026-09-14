import SwiftUI
import MeterCore

@MainActor enum PaymentDraftUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-payment-draft-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:folder)}
        var failures=0
        func check(_ ok:Bool,_ name:String) {print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle() {
            let deadline=Date().addingTimeInterval(0.6)
            while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}
        }
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap{descendants($0)} }
        let calendar=Calendar.current
        func date(_ month:Int)->Date {calendar.date(from:DateComponents(year:2027,month:month,day:7))!}
        let paid=Payment(amount:6000,start:date(1),end:date(4))
        do {try Database().savePayment(paid)} catch {check(false,"Create isolated payment history: \(error)");return false}
        let store=MeterStore(startServices:false)
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:980,height:740),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer {if let sheet=window.attachedSheet {window.endSheet(sheet)};window.orderOut(nil)}
        let host=NSHostingView(rootView:PaymentsView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        UIAccessibility.press(UIAccessibility.find(host,"payment-add"));settle()
        guard let sheet=window.attachedSheet,let content=sheet.contentView else {check(false,"Add payment opens a real sheet");return false}
        let dates=descendants(content).compactMap{$0 as? NSDatePicker}.map(\.dateValue).sorted()
        check(dates==[date(4),date(5)],"Add payment pre-fills the month after the latest multi-month payment")
        let amount=descendants(content).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Фактически уплачено, ₽"}
        check(amount != nil && amount?.stringValue=="","New payment keeps the amount empty instead of copying a prior charge")
        UIAccessibility.capture(content,"payment-next-month")
        amount?.selectText(nil)
        if let editor=amount?.currentEditor() as? NSTextView {editor.insertText("2000",replacementRange:editor.selectedRange())}
        settle();UIAccessibility.press(UIAccessibility.find(content,"payment-save"));settle()
        let payments=(try? Database().payments()) ?? []
        check(payments.count==2 && payments.contains{$0.start==date(4) && $0.end==date(5) && $0.amount==2000} && payments.contains{$0.id==paid.id && $0.amount==6000},"Entering only the amount saves the suggested month and preserves the previous payment")
        return failures==0
    }
}
