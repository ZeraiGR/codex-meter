import Foundation
import SwiftUI
import MeterCore
import UserNotifications
import ServiceManagement

if CommandLine.arguments.dropFirst().first=="ui-check" {
    let passed=MainActor.assumeIsolated {UISmokeChecks.run()}
    exit(passed ? 0:1)
} else if CommandLine.arguments.dropFirst().first=="diagnostics" {
    let login=SMAppService.mainApp.status.rawValue
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        print("{\"loginStatus\":\(login),\"notificationAuthorization\":\(settings.authorizationStatus.rawValue),\"notificationAlerts\":\(settings.alertSetting.rawValue)}")
        exit(0)
    }
    DispatchQueue.global().asyncAfter(deadline:.now()+8){fputs("System settings did not respond\n",stderr);exit(1)}
    dispatchMain()
} else if CommandLine.arguments.count>2 && CommandLine.arguments[1]=="render" {
    MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let store=MeterStore(startServices:false)
    if let error=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_ERROR"] {store.error=error}
    let isDashboard=CommandLine.arguments.count>3
    if isDashboard {store.tab=CommandLine.arguments[3];let db=try? Database();store.tasks=(try? db?.summaries()) ?? [];store.runs=(try? db?.runs()) ?? []}
    let size=NSSize(width:isDashboard ? 980:420,height:isDashboard ? 740:550)
    let content=Group {if isDashboard {DashboardView()} else {PopoverView()}}.environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")).frame(width:size.width,height:size.height).background(Color(nsColor:.windowBackgroundColor))
    let host=NSHostingView(rootView:content)
    let window=NSWindow(contentRect:NSRect(origin:NSPoint(x:-10000,y:-10000),size:size),styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView=host;window.orderFrontRegardless()
    RunLoop.current.run(until:Date().addingTimeInterval(1))
    host.layoutSubtreeIfNeeded()
    let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds)
    if let rep {host.cacheDisplay(in:host.bounds,to:rep)}
    if let png=rep?.representation(using:.png,properties:[:]) {
        do{try png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]));print(CommandLine.arguments[2])}catch{fputs(error.localizedDescription,stderr);exit(1)}
    } else {fputs("Could not render view\n",stderr);exit(1)}
    window.orderOut(nil)
    }
} else if CommandLine.arguments.count>1 && !CommandLine.arguments[1].hasPrefix("-psn") {
    do { print(try Commands.run(Array(CommandLine.arguments.dropFirst()))) }
    catch {
        if CommandLine.arguments[1]=="hook" { print("{}") }
        else { FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1) }
    }
} else { MeterApp.main() }
