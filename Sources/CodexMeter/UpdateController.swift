import SwiftUI
import Combine
import Sparkle
import UserNotifications

/// Sparkle owns discovery, authenticated download, installation and relaunch.
/// This adapter adds reminders for an app that normally has no Dock icon.
@MainActor final class UpdateController:NSObject,ObservableObject,@preconcurrency SPUUpdaterDelegate,@preconcurrency SPUStandardUserDriverDelegate {
    static let notificationID="codex-meter.software-update"
    @Published private(set) var availableVersion:String?
    @Published private(set) var canCheck=false
    @Published private(set) var automaticChecks=true
    @Published private(set) var lastChecked:Date?
    @Published private(set) var issue:String?
    private var controller:SPUStandardUpdaterController?
    private var schedule:UpdateCheckScheduler?
    private var probing=false
    var currentVersion:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—"}

    init(enabled:Bool) {
        super.init()
        guard enabled else{return}
        let controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:self)
        self.controller=controller
        controller.updater.publisher(for:\.canCheckForUpdates).assign(to:&$canCheck)
        controller.updater.publisher(for:\.automaticallyChecksForUpdates).assign(to:&$automaticChecks)
        controller.updater.publisher(for:\.lastUpdateCheckDate).assign(to:&$lastChecked)
        do {
            try controller.updater.start()
            let schedule=UpdateCheckScheduler(
                enabled:{[weak self] in self?.controller?.updater.automaticallyChecksForUpdates == true},
                busy:{[weak self] in self?.controller?.updater.sessionInProgress != false},
                check:{[weak self] in self?.probe()})
            self.schedule=schedule;schedule.start()
        } catch {issue="Не удалось запустить проверку обновлений: \(error.localizedDescription)"}
    }
    func check() {
        guard let controller else{return}
        WindowNavigation.shared.dismissPopover()
        NSApp.activate(ignoringOtherApps:true)
        issue=nil
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled:Bool) {
        controller?.updater.automaticallyChecksForUpdates=enabled
        if enabled {schedule?.checkNow()}
    }
    private func probe() {
        guard let updater=controller?.updater,updater.automaticallyChecksForUpdates,!updater.sessionInProgress else{return}
        probing=true;updater.checkForUpdateInformation()
    }
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) {
        guard probing else{return}
        availableVersion=item.displayVersionString
        announce(item)
    }
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {
        guard updateCheck == .updateInformation else{return}
        probing=false
        if let error=error as NSError? {
            if error.code == SUError.noUpdateError.rawValue {availableVersion=nil;issue=nil}
            else {issue="Проверка обновлений не завершена. Повторите позже."}
        } else {issue=nil}
    }
    var supportsGentleScheduledUpdateReminders:Bool {true}
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update:SUAppcastItem,andInImmediateFocus immediateFocus:Bool)->Bool {false}
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate:Bool,forUpdate update:SUAppcastItem,state:SPUUserUpdateState) {
        availableVersion=update.displayVersionString
        guard !state.userInitiated else{return}
        announce(update)
    }
    private func announce(_ update:SUAppcastItem) {
        Task {
            let center=UNUserNotificationCenter.current()
            let permission=await center.notificationSettings()
            guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else{return}
            // A version is notified once, after successful delivery to the system.
            let key="lastNotifiedSoftwareBuild"
            guard UserDefaults.standard.string(forKey:key) != update.versionString else{return}
            let content=UNMutableNotificationContent()
            content.title="Доступно обновление Codex Meter"
            content.body="Версия \(update.displayVersionString) готова. Нажмите, чтобы посмотреть изменения и установить."
            do {
                try await center.add(UNNotificationRequest(identifier:Self.notificationID,content:content,trigger:nil))
                UserDefaults.standard.set(update.versionString,forKey:key)
            } catch { /* The in-app reminder remains available if macOS refuses delivery. */ }
        }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update:SUAppcastItem) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:[Self.notificationID])
    }
    func standardUserDriverWillFinishUpdateSession() {availableVersion=nil}
    func updater(_ updater:SPUUpdater,didAbortWithError error:Error) {
        let error=error as NSError
        guard error.code != SUError.noUpdateError.rawValue else {issue=nil;return}
        issue="Проверка обновлений не завершена. Повторите позже."
    }
}

struct SoftwareUpdateCard:View {
    @ObservedObject var updater:UpdateController
    var body:some View {
        Card {
            HStack {Text("Обновления приложения").font(.headline);Spacer();Text("v\(updater.currentVersion)").foregroundStyle(MeterTheme.secondary)}
            if let version=updater.availableVersion {Label("Доступна версия \(version)",systemImage:"arrow.down.circle.fill").foregroundStyle(MeterTheme.accent)}
            Toggle("Проверять обновления автоматически",isOn:Binding(get:{updater.automaticChecks},set:updater.setAutomaticChecks))
            Text("Проверяем каждые 15 минут, при запуске и после пробуждения Mac. Установка — по вашему выбору, с перезапуском приложения.").font(.caption).foregroundStyle(MeterTheme.secondary)
            if let date=updater.lastChecked {Text("Последняя проверка: \(date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(MeterTheme.secondary)}
            if let issue=updater.issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.warning)}
            Button(updater.availableVersion == nil ? "Проверить обновления…":"Посмотреть обновление…",action:updater.check)
                .disabled(!updater.canCheck).accessibilityIdentifier("software-update-check")
        }
    }
}
