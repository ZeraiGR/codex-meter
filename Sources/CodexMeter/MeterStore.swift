import Foundation
import Combine
import SwiftUI
import UserNotifications
import ServiceManagement
import MeterCore

@MainActor final class MeterStore:ObservableObject {
    @Published var snapshot:AccountSnapshot?
    @Published var tasks:[TaskSummary]=[]
    @Published var runs:[RunRecord]=[]
    @Published var payments:[Payment]=[]
    @Published var error:String?
    @Published var updating=false
    @Published var loadingHistory=false
    @Published private(set) var activity:String?
    var isPerformingAction:Bool { activity != nil }
    @Published var tab="tasks"
    @Published var notifications=false
    @Published var notificationIssue:String?
    @Published var loginEnabled=false
    @Published var thresholds="50, 80, 90, 95"
    @Published var codexPath=""
    @Published var connectionError:String?
    @Published var integrationInstalled=false
    @Published var expiryReminder=true
    @Published var expiryDays=2
    @Published var expiryRemaining=35
    @Published var lastDayRemaining=35
    let updates:UpdateController
    private var updateObservation:AnyCancellable?
    private var timer:Timer?
    private var networkTicks=0
    private var localBusy=false
    private var historyLoaded=false
    private var localReload:Task<Void,Never>?
    private let notificationDelegate=MeterNotificationDelegate()
    private let directory=Database.defaultDirectory
    var currentPayment:Payment? {payments.first{$0.contains(Date())}}
    var remaining:Double? { snapshot?.main?.windows.filter{$0.valid(at:Date())}.map(\.remaining).min() }
    var money:(current:Double,future:Double)? {
        guard let window=snapshot?.moneyWindow,snapshot?.fresh()==true else{return nil}
        return currentPayment?.available(window:window,now:Date())
    }
    init(startServices:Bool = true) {
        updates=UpdateController(enabled:startServices)
        do {
            let db=try Database();snapshot=try db.snapshot();payments=try db.payments()
            notifications=try db.value("notifications") != "false"
            let issue=try db.value("notificationIssue") ?? ""
            notificationIssue=issue.isEmpty ? nil:issue
            thresholds=try db.value("thresholds") ?? "50, 80, 90, 95"
            codexPath=try db.value("codexPath") ?? ""
            expiryReminder=try db.value("expiryReminder") != "false"
            expiryDays=Int(try db.value("expiryDays") ?? "2") ?? 2
            expiryRemaining=Int(try db.value("expiryRemaining") ?? "35") ?? 35
            lastDayRemaining=Int(try db.value("lastDayRemaining") ?? "35") ?? 35
            integrationInstalled=FileManager.default.fileExists(atPath:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/skills/codex-meter/SKILL.md").path)
        } catch {self.error=error.localizedDescription}
        loginEnabled=SMAppService.mainApp.status == .enabled
        updateObservation=updates.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        guard startServices else{return}
        notificationDelegate.openUpdate={ [weak self] in self?.updates.check() }
        UNUserNotificationCenter.current().delegate=notificationDelegate
        timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else{return};self.networkTicks += 1
                self.reloadLocal()
                if self.networkTicks%4==0 {self.refresh()}
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task{@MainActor in self?.refresh();self?.reloadLocal()}
        }
        reloadLocal();refresh()
        Task {
            let db=try? Database()
            if (try? db?.value("onboarded")) == nil {
                if notifications {await enableNotifications(true)}
                setLogin(true)
                try? db?.set("onboarded","true")
            } else {
                let settings=await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
                    notifications=false
                    notificationIssue=settings.authorizationStatus == .denied
                        ? "macOS запрещает уведомления. Откройте Системные настройки → Уведомления → Codex Meter, разрешите их, затем включите переключатель выше."
                        : "Для предупреждений включите переключатель выше и разрешите уведомления в запросе macOS."
                    try? db?.set("notifications","false")
                    try? db?.set("notificationIssue",notificationIssue ?? "")
                }
            }
        }
    }
    func reloadLocal() {
        guard !localBusy,!isPerformingAction else{return};localBusy=true;loadingHistory = !historyLoaded
        localReload=Task {
            do {
                let result=try await Task.detached(priority:.utility) { [directory] in
                    let db=try Database(directory:directory);_ = try Journal.sync(db:db)
                    return (try db.summaries(),try db.runs(),try db.payments())
                }.value
                tasks=result.0;runs=result.1;payments=result.2;historyLoaded=true
            } catch {self.error=error.localizedDescription}
            localBusy=false;loadingHistory=false
        }
    }
    func refresh() {
        guard !updating else{return};updating=true
        Task {
            do {
                let value=try await Task.detached(priority:.utility) { [directory] in
                    let db=try Database(directory:directory),value=try CodexClient.fetch(db:db)
                    try db.saveSnapshot(value);return value
                }.value
                snapshot=value;error=nil;connectionError=nil
                await notifyIfNeeded(value)
                reloadLocal()
            } catch {self.error=error.localizedDescription;connectionError=error.localizedDescription}
            updating=false
        }
    }
    /// Acquire the gate before creating a Task: two clicks in one event-loop turn
    /// must not queue two writes. Keep it until the displayed summaries are current.
    @discardableResult
    func performAction(_ title:String,operation:@escaping @Sendable (Database)throws->Void,
                       completion:@escaping (Result<Void,Error>)->Void = {_ in}) -> Bool {
        guard !isPerformingAction else{return false}
        activity=title
        let pendingReload=localReload
        Task {
            await pendingReload?.value
            defer {activity=nil}
            do {
                let result=try await Task.detached(priority:.userInitiated) { [directory] in
                    let db=try Database(directory:directory)
                    // Keep both the write and the resulting summary atomic. A
                    // failed recalculation must leave the dialog safe to retry.
                    return try db.transaction {
                        try operation(db)
                        return (try db.summaries(),try db.runs(),try db.payments())
                    }
                }.value
                tasks=result.0;runs=result.1;payments=result.2;historyLoaded=true
                completion(.success(()))
            } catch {completion(.failure(error))}
        }
        return true
    }
    func savePayment(_ payment:Payment,completion:@escaping (Result<Void,Error>)->Void) {
        performAction("Сохраняем платёж и пересчитываем стоимость…",operation: {try $0.savePayment(payment)},completion:completion)
    }
    func saveTask(_ task:WorkTask,completion:@escaping (Result<Void,Error>)->Void) {
        performAction("Сохраняем задачу…",operation: {try $0.saveTask(task)},completion:completion)
    }
    func assign(_ run:RunRecord,to task:WorkTask,completion:@escaping (Result<Void,Error>)->Void) {
        performAction("Добавляем запрос и пересчитываем задачу…",operation: {db in
            if try db.task(task.id)==nil {try db.saveTask(task)}
            try db.bind(thread:run.thread,turn:run.id,task:task.id)
        },completion:completion)
    }
    func merge(_ source:String,_ target:String,completion:@escaping (Result<Void,Error>)->Void) {
        performAction("Объединяем задачи и пересчитываем статистику…",operation: {try $0.mergeTasks(source:source,target:target)},completion:completion)
    }
    func saveAlertSettings() throws {
        let parts=thresholds.split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}
        let values=parts.compactMap(Int.init)
        guard !values.isEmpty,values.count==parts.count,values.allSatisfy({$0>0 && $0<100}) else {throw MeterError("Пороги — целые проценты расхода от 1 до 99 через запятую")}
        let db=try Database();try db.set("thresholds",values.sorted().map(String.init).joined(separator:", "))
        try db.set("expiryReminder",expiryReminder ? "true":"false")
        try db.set("expiryDays",String(expiryDays));try db.set("expiryRemaining",String(expiryRemaining));try db.set("lastDayRemaining",String(lastDayRemaining))
        thresholds=values.sorted().map(String.init).joined(separator:", ")
    }
    func saveCodexPath(_ value:String) throws {
        let path=(value.trimmingCharacters(in:.whitespacesAndNewlines) as NSString).expandingTildeInPath
        if !path.isEmpty {
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:path,isDirectory:&directory),!directory.boolValue,
                  FileManager.default.isExecutableFile(atPath:path) else {
                throw MeterError("Выберите исполняемый файл codex. Папка или обычный документ не подходят.")
            }
        }
        try Database().set("codexPath",path)
        codexPath=path
    }
    func setLogin(_ enabled:Bool) {
        do {
            if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
            loginEnabled=SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled {error="Разрешите автозапуск в Системных настройках → Основные → Объекты входа."}
        } catch {self.error="Автозапуск: \(error.localizedDescription)";loginEnabled=SMAppService.mainApp.status == .enabled}
    }
    func enableNotifications(_ enabled:Bool) async {
        do {
            notifications=enabled ? try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) : false
            try Database().set("notifications",notifications ? "true":"false")
            notificationIssue=enabled && !notifications ? "Уведомления запрещены macOS. Разрешите их для Codex Meter в Системных настройках.":nil
            try Database().set("notificationIssue",notificationIssue ?? "")
        } catch {
            notifications=false;notificationIssue="macOS не разрешила уведомления: \(error.localizedDescription)"
            try? Database().set("notifications","false");try? Database().set("notificationIssue",notificationIssue ?? "")
        }
    }
    private func notifyIfNeeded(_ snapshot:AccountSnapshot) async {
        guard notifications,snapshot.fresh() else{return}
        do {
            let db=try Database(),values=thresholds.split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces))}
            for bucket in snapshot.buckets {
                for window in bucket.windows {
                    let key=try db.alertKey(account:snapshot.accountKey,bucket:bucket.id,window:window)
                    let sent=Set((try db.value(key) ?? "").split(separator:",").compactMap{Int($0)})
                    let crossed=AlertPolicy.pending(window:window,thresholds:values,sent:sent,now:Date())
                    if let threshold=crossed.last {
                        let content=UNMutableNotificationContent()
                        content.title=threshold==50 ? "Израсходовано \(Int(window.usedPercent))% квоты \(bucket.title)":"Осталось \(Int(window.remaining))% квоты \(bucket.title)"
                        content.body="\(window.label). Восстановление \(window.resetDate?.formatted(date:.abbreviated,time:.shortened) ?? "уточняется")."
                        content.sound=threshold>=80 ? .default:nil
                        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:key,content:content,trigger:nil))
                        try db.set(key,sent.union(crossed).sorted().map(String.init).joined(separator:","))
                    }
                    if expiryReminder,bucket.id=="codex",window.windowDurationMins==10080 {
                        let stages=[(expiryDays,expiryRemaining),(1,lastDayRemaining)]
                        // After sleep, deliver only the most urgent eligible reminder.
                        let eligible=stages.filter { stage in
                            AlertPolicy.expiring(window:window,days:stage.0,minimumRemaining:stage.1,now:Date()) && (try? db.value("expiry:\(key):\(stage.0)")) == nil
                        }.sorted{$0.0<$1.0}
                        if let stage=eligible.first {
                            let content=UNMutableNotificationContent()
                            content.title="До восстановления квоты меньше \(stage.0 == 1 ? "суток":"\(stage.0) дней")"
                            content.body="Осталось \(Int(window.remaining))% недельной квоты. Можно запланировать отложенные задачи до \(window.resetDate!.formatted(date:.abbreviated,time:.shortened))."
                            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"expiry:\(key):\(stage.0)",content:content,trigger:nil))
                            for old in stages where old.0>=stage.0 {try db.set("expiry:\(key):\(old.0)","sent")}
                        }
                    }
                }
            }
        } catch {self.error="Уведомления: \(error.localizedDescription)"}
    }
    func forecast(_ kind:String) -> Forecast {Predictor.estimate(kind:kind,history:tasks,snapshot:snapshot,payment:currentPayment)}
}

enum Format {
    static func tokens(_ value:Int64) -> String {
        if value>=1_000_000_000 {return String(format:"%.2f млрд",locale:Locale(identifier:"ru_RU"),Double(value)/1_000_000_000)}
        if value>=1_000_000 {return String(format:"%.2f млн",locale:Locale(identifier:"ru_RU"),Double(value)/1_000_000)}
        if value>=1000 {return String(format:"%.1f тыс.",locale:Locale(identifier:"ru_RU"),Double(value)/1000)}
        return "\(value)"
    }
    static func rub(_ value:Double?) -> String {guard let value else{return "—"};return value.formatted(.currency(code:"RUB").locale(Locale(identifier:"ru_RU")).precision(.fractionLength(0...2)))}
    static func time(_ seconds:Double) -> String {
        let seconds=Int(max(0,seconds));if seconds<60{return "\(seconds) с"}
        if seconds<3600{return "\(seconds/60) мин"}
        if seconds>=86400{return "\(seconds/86400) дн. \((seconds%86400)/3600) ч"}
        return "\(seconds/3600) ч \((seconds%3600)/60) мин"
    }
    static func status(_ s:String) -> String {["active":"В работе","paused":"Ожидает","completed":"Завершена","cancelled":"Отменена","failed":"Не удалась"][s] ?? s}
    static func color(_ remaining:Double?) -> Color {guard let remaining else{return .secondary};return remaining<=10 ? MeterTheme.danger:remaining<=50 ? MeterTheme.warning:MeterTheme.accent}
}

private final class MeterNotificationDelegate:NSObject,UNUserNotificationCenterDelegate {
    var openUpdate:(@MainActor ()->Void)?
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        if response.notification.request.identifier == "codex-meter.software-update" && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.openUpdate?();completionHandler() }
        } else {completionHandler()}
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.sound])
    }
}
