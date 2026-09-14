import SwiftUI
import MeterCore

@MainActor enum ThemeUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-theme-\(UUID().uuidString)")
        let oldHome=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        let oldTask=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_TASK"]
        setenv("CODEX_METER_HOME",folder.path,1);setenv("CODEX_METER_RENDER_TASK","demo-review",1)
        defer {
            if let oldHome {setenv("CODEX_METER_HOME",oldHome,1)} else {unsetenv("CODEX_METER_HOME")}
            if let oldTask {setenv("CODEX_METER_RENDER_TASK",oldTask,1)} else {unsetenv("CODEX_METER_RENDER_TASK")}
            try? FileManager.default.removeItem(at:folder)
        }
        let store=MeterStore(startServices:false)
        let quota=QuotaWindow(usedPercent:37,windowDurationMins:10080,resetsAt:Date().addingTimeInterval(86400*4).timeIntervalSince1970)
        store.snapshot=AccountSnapshot(accountKey:"synthetic",buckets:[QuotaBucket(primary:quota)])
        store.payments=[Payment(amount:3000,start:Date().addingTimeInterval(-86400*7),end:Date().addingTimeInterval(86400*23))]
        let task=WorkTask(id:"demo-review",title:"Ревью API заказов",kind:"code-review",status:"completed")
        let run=RunRecord(id:"demo-run",thread:"demo",started:Date().addingTimeInterval(-1800),ended:Date(),tokens:TokenCount(input:450000,cached:300000,output:32000),model:"Codex",title:"Проверить обработку ошибок",outcome:"completed",taskID:task.id)
        store.tasks=[TaskSummary(task:task,runs:[run],quotaPoints:3.5,rubles:24.5,quotaQuality:"Полное покрытие",weeklyQuota:WeeklyQuotaUsage(points:3.5,coverage:1,windowCount:1))]
        var failures=0
        func luminance(_ color:Color)->Double {
            guard let rgb=NSColor(color).usingColorSpace(.sRGB) else{return -1}
            func linear(_ value:Double)->Double {value<=0.04045 ? value/12.92:pow((value+0.055)/1.055,2.4)}
            return 0.2126*linear(rgb.redComponent)+0.7152*linear(rgb.greenComponent)+0.0722*linear(rgb.blueComponent)
        }
        let oldAppearance=NSApp.appearance
        defer {NSApp.appearance=oldAppearance}
        for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",.darkAqua)] {
            let style=NSAppearance(named:appearance)!
            NSApp.appearance=style
            var minimum=Double.infinity
            style.performAsCurrentDrawingAppearance {
                for foreground in [MeterTheme.accent,MeterTheme.warning,MeterTheme.danger,MeterTheme.secondary] {
                    for background in [MeterTheme.background,MeterTheme.surface] {
                        let first=luminance(foreground),second=luminance(background)
                        minimum=min(minimum,(max(first,second)+0.05)/(min(first,second)+0.05))
                    }
                }
            }
            let ok=minimum>=4.5
            print("\(ok ? "PASS":"FAIL") \(name) semantic text contrast at least 4.5:1 (minimum \(String(format:"%.2f",minimum)))")
            if !ok {failures += 1}
            for dashboard in [false,true] {
                let size=NSSize(width:dashboard ? 980:420,height:dashboard ? 740:550)
                let host=NSHostingView(rootView:Group {if dashboard {DashboardView()} else {PopoverView()}}.environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")))
                let window=NSWindow(contentRect:NSRect(origin:NSPoint(x:-10000,y:-10000),size:size),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.appearance=style;window.contentView=host;NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until:Date().addingTimeInterval(0.3))
                UIAccessibility.capture(host,"theme-\(name)-\(dashboard ? "tasks":"popover")")
                window.orderOut(nil)
            }
        }
        return failures==0
    }
}
