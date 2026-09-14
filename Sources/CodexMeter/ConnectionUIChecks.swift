import SwiftUI
import MeterCore

@MainActor enum ConnectionUIChecks {
    static func run()->Bool {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meter-connection-\(UUID().uuidString)")
        let old=ProcessInfo.processInfo.environment["CODEX_METER_HOME"]
        setenv("CODEX_METER_HOME",folder.path,1)
        defer {if let old {setenv("CODEX_METER_HOME",old,1)} else {unsetenv("CODEX_METER_HOME")};try? FileManager.default.removeItem(at:folder)}
        let store=MeterStore(startServices:false)
        store.snapshot=AccountSnapshot(accountKey:"demo",fetchedAt:Date(),buckets:[])
        var failures=0
        func check(_ ok:Bool,_ name:String) {print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle() {
            let deadline=Date().addingTimeInterval(0.4)
            while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}
        }
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap{descendants($0)} }
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:640),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer {window.orderOut(nil)}
        let host=NSHostingView(rootView:ConnectionCard().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU")).padding(20).frame(width:660).background(Color(nsColor:.windowBackgroundColor)))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        func text()->String {
            UIAccessibility.nodes(host).flatMap { node in
                ["accessibilityValue","accessibilityLabel","accessibilityTitle"].compactMap { UIAccessibility.value(node,$0) as? String }
            }.joined(separator:" ")
        }
        func pathField()->NSTextField? {
            descendants(host).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Например: /opt/homebrew/bin/codex"}
        }
        check(text().contains("Данные Codex актуальны") && pathField()==nil,"Automatic connection explains its working state without an empty path field")
        UIAccessibility.capture(host,"connection-automatic")
        store.connectionError="Temporary error";settle()
        check(text().contains("Не удалось обновить данные") && !text().contains("Данные Codex актуальны"),"Latest connection failure is visible even while the previous snapshot is fresh")
        store.connectionError=nil;store.snapshot?.fetchedAt=Date().addingTimeInterval(-600);settle()
        check(text().contains("Данные требуют обновления"),"Old snapshot is not labelled as a working connection")
        store.snapshot?.fetchedAt=Date()
        let toggle=UIAccessibility.nodes(host).first { node in
            let role=UIAccessibility.value(node,"accessibilityRole") as? String
            let label=(UIAccessibility.value(node,"accessibilityLabel") as? String) ?? (UIAccessibility.value(node,"accessibilityTitle") as? String) ?? ""
            return (role=="AXDisclosureTriangle" || role=="AXButton") && label.contains("Дополнительные настройки")
        }
        UIAccessibility.press(toggle ?? UIAccessibility.find(host,"connection-advanced"));settle()
        let modes=descendants(host).compactMap{$0 as? NSSegmentedControl}.first{$0.segmentCount==2}
        check(modes != nil && pathField()==nil,"Advanced settings default to automatic search without asking for a path")
        modes?.selectedSegment=1
        if let modes {modes.sendAction(modes.action,to:modes.target)};settle()
        check(pathField() != nil && !UIAccessibility.enabled(UIAccessibility.find(host,"connection-apply")),"Manual search reveals a labelled file field and rejects an empty choice")
        UIAccessibility.capture(host,"connection-manual")
        do {
            let db=try Database()
            do {try store.saveCodexPath(folder.path);check(false,"Directory cannot be saved as Codex")} catch {check((try? db.value("codexPath"))==nil,"Directory is rejected without modifying the saved connection")}
            let executable=folder.appendingPathComponent("codex")
            try Data().write(to:executable);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
            try store.saveCodexPath("  "+executable.path+"\n")
            check(store.codexPath==executable.path && (try? db.value("codexPath"))==executable.path && (try? CodexClient.executable(db:db))==executable,"Manual path is normalized, persisted and used by the resolver")
            try FileManager.default.removeItem(at:executable)
            store.thresholds="50, 75, 90";try store.saveAlertSettings()
            check((try? db.value("thresholds"))=="50, 75, 90" && (try? db.value("codexPath"))==executable.path,"Saving notification thresholds neither changes nor validates the connection path")
            do {_ = try CodexClient.executable(db:db);check(false,"Missing manual file reports an actionable error")} catch {check(error.localizedDescription.contains("автоматический поиск"),"Missing manual file reports an actionable error instead of silently choosing another installation")}
            try store.saveCodexPath("")
            check((try? db.value("codexPath"))=="" && (try? db.value("thresholds"))=="50, 75, 90","Returning to automatic search preserves notification settings")
        } catch {check(false,"Connection persistence checks: \(error)")}
        return failures==0
    }
}
