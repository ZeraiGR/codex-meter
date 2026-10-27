import SwiftUI
import MeterCore

@MainActor enum TelegramUIChecks {
    static func run()->Bool {
        final class Backend:@unchecked Sendable {
            let lock=NSLock()
            var value:[String:Any]=["connected":false,"running":false,"owner_id":0,"pending_url":"","permissions":["limits":true,"reminders":true,"window_changes":true,"codex":false]]
            var failSave=false
            var requests:[[String:Any]]=[]
            func call(_ request:[String:Any])throws->[String:Any] {
                lock.lock();defer{lock.unlock()};requests.append(request)
                switch request["action"] as? String {
                case "begin":value["pending_url"]="https://t.me/synthetic_bot?start=synthetic"
                case "pair":value["pending_url"]="";value["connected"]=true;value["running"]=true;value["username"]="synthetic_bot";value["owner_id"]=123
                case "save":
                    if failSave {return ["error":"Синтетическая ошибка сохранения"]}
                    value["permissions"]=request["permissions"]
                default:break
                }
                return value
            }
        }
        let backend=Backend(),model=TelegramSettings(bridge:{request,_,_ in try backend.call(request)})
        var failures=0
        func check(_ ok:Bool,_ name:String){print("\(ok ? "PASS":"FAIL") \(name)");if !ok {failures += 1}}
        func settle(_ seconds:Double=0.4){let deadline=Date().addingTimeInterval(seconds);while Date()<deadline {if let event=NSApp.nextEvent(matching:.any,until:deadline,inMode:.default,dequeue:true){NSApp.sendEvent(event)};NSApp.updateWindows()}}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:720,height:850),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;defer{window.orderOut(nil)}
        let host=NSHostingView(rootView:ScrollView{TelegramSettingsCard(model:model).padding(20)}.background(MeterTheme.background))
        window.contentView=host;window.makeKeyAndOrderFront(nil);settle()
        check(!model.connected && !model.codexRequests,"Fresh Telegram settings have no owner and do not allow Codex execution")
        check(UIAccessibility.find(host,"telegram-permission-codex")==nil,"Standard Telegram settings do not expose Codex execution")
        check(!UIAccessibility.enabled(UIAccessibility.find(host,"telegram-connect")),"Connecting requires an explicit bot token")
        for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",NSAppearance.Name.darkAqua)] {
            window.appearance=NSAppearance(named:appearance);settle();UIAccessibility.capture(host,"telegram-settings-new-"+name)
        }
        model.token="synthetic-token";settle()
        UIAccessibility.press(UIAccessibility.find(host,"telegram-connect"));settle()
        check(model.token.isEmpty && UIAccessibility.find(host,"telegram-pair-link") != nil,"Token is cleared and explicit owner confirmation link appears")
        check(!model.connected,"Token validation alone does not connect an owner")
        UIAccessibility.capture(host,"telegram-settings-pair")
        UIAccessibility.press(UIAccessibility.find(host,"telegram-pair-check"));settle()
        check(model.connected && model.ownerID==123 && model.running,"Checking Start exposes the paired owner and enabled service")
        model.limits=false;settle()
        backend.failSave=true
        UIAccessibility.press(UIAccessibility.find(host,"telegram-save"));settle()
        check(model.issue != nil && !model.limits && !model.busy,"Failed permission save keeps the draft and restores controls")
        backend.failSave=false
        UIAccessibility.press(UIAccessibility.find(host,"telegram-save"));settle()
        check(model.issue==nil && !model.limits && backend.value["permissions"] as? [String:Bool] == ["limits":false,"reminders":true,"window_changes":true,"codex":false],"Retry saves independent Telegram permissions")
        for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",NSAppearance.Name.darkAqua)] {
            window.appearance=NSAppearance(named:appearance);settle();UIAccessibility.capture(host,"telegram-settings-connected-"+name)
        }
        check(backend.requests.allSatisfy{($0["action"] as? String) != "disconnect"},"Inspecting settings never disconnects the user's bot")
        return failures==0
    }
}
