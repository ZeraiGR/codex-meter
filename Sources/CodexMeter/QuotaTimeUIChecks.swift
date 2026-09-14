import SwiftUI
import MeterCore

@MainActor enum QuotaTimeUIChecks {
    static func run()->Bool {
        var failures=0
        func check(_ ok:Bool,_ label:String) {print("\(ok ? "PASS":"FAIL") \(label)");if !ok {failures += 1}}
        func settle() {
            let deadline=Date().addingTimeInterval(0.4)
            while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}
        }
        let now=Date(),duration=604800.0
        let quota=QuotaWindow(usedPercent:37,windowDurationMins:10080,resetsAt:now.timeIntervalSince1970+duration*0.69)
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:420,height:180),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:QuotaRowContent(window:quota,now:now).padding(18).frame(width:420).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        func value(_ id:String)->String? {
            UIAccessibility.find(host,id).flatMap { UIAccessibility.value($0,"accessibilityValue") as? String }
        }
        check(value("quota-time-caption")=="31% прошло · 69% осталось" && value("quota-remaining-caption")=="37% потрачено · 63% осталось","Quota and elapsed week percentages are distinct and comparable")
        if let time=UIAccessibility.find(host,"quota-time-bar"),let resource=UIAccessibility.find(host,"quota-remaining-bar") {
            let a=UIAccessibility.frame(time),b=UIAccessibility.frame(resource)
            check(a.width>300 && abs(a.width-b.width)<1 && abs(a.minX-b.minX)<1 && !a.intersects(b),"Quota and time bars share the same scale and occupy separate rows")
        } else {check(false,"Both accessible quota bars exist")}
        if let label=UIAccessibility.find(host,"quota-time-caption"),let reset=UIAccessibility.find(host,"quota-reset-date") {
            check(!UIAccessibility.frame(label).intersects(UIAccessibility.frame(reset)),"Week percentages do not overlap the reset date")
        } else {check(false,"Time percentage and reset date are accessible")}
        host.rootView=QuotaRowContent(window:quota,now:now.addingTimeInterval(duration)).padding(18).frame(width:420).background(Color(nsColor:.windowBackgroundColor));settle()
        check(value("quota-time-caption")==nil && value("quota-reset-message")?.contains("Период завершён")==true,"Expired window waits for a server reset instead of starting an invented week")
        host.rootView=QuotaRowContent(window:QuotaWindow(usedPercent:37,windowDurationMins:nil,resetsAt:nil),now:now).padding(18).frame(width:420).background(Color(nsColor:.windowBackgroundColor));settle()
        check(value("quota-time-caption")==nil && value("quota-time-bar")==nil,"Unknown duration and reset do not show a fabricated time percentage")

        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("meter-quota-time-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",directory.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:directory)}
        let store=MeterStore(startServices:false)
        store.snapshot=AccountSnapshot(accountKey:"demo",fetchedAt:now,buckets:[QuotaBucket(primary:quota)])
        store.payments=[Payment(id:"demo",amount:6000,start:now.addingTimeInterval(-duration*0.31),end:now.addingTimeInterval(duration*3.69))]
        let popover=NSHostingView(rootView:PopoverView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")).background(Color(nsColor:.windowBackgroundColor)))
        window.setContentSize(NSSize(width:420,height:550));window.contentView=popover;settle()
        check(UIAccessibility.find(popover,"quota-time-caption") != nil && popover.bounds.height<=550,"Week progress is present in the standard-size menu popover")
        UIAccessibility.capture(popover,"quota-week-progress")
        return failures==0
    }
}
