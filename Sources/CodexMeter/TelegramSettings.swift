import SwiftUI
import MeterCore

@MainActor final class TelegramSettings:ObservableObject {
    @Published var connected=false
    @Published var running=false
    @Published var requestsRunning=false
    @Published var username=""
    @Published var ownerID:Int64=0
    @Published var pendingURL=""
    @Published var token=""
    @Published var workspace=""
    @Published var codex=""
    @Published var sandbox="read-only"
    @Published var limits=true
    @Published var reminders=true
    @Published var windowChanges=true
    @Published var codexRequests=false
    @Published var maxParallel=3
    @Published var reminderHours="48, 24, 6"
    @Published var tunnelPort=""
    @Published var python=UserDefaults.standard.string(forKey:"telegramPython") ?? ""
    @Published var busy=false
    @Published var issue:String?
    @Published var notice:String?
    private let directory:URL
    private let bridge:@Sendable ([String:Any],String,URL)throws->[String:Any]

    init(directory:URL=Database.defaultDirectory.appendingPathComponent("telegram"),
         bridge:@escaping @Sendable ([String:Any],String,URL)throws->[String:Any]={try TelegramSettings.invoke($0,$1,$2)}) {
        self.directory=directory;self.bridge=bridge
    }

    func perform(_ action:String) {
        guard !busy else{return}
        issue=nil;notice=nil
        var request:[String:Any]=["action":action]
        if action=="begin" || action=="save" {
            let pieces=reminderHours.split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}
            let hours=pieces.compactMap(Int.init)
            guard (!reminders || !hours.isEmpty),hours.count==pieces.count,hours.allSatisfy({(1...168).contains($0)}) else {issue="Укажите часы через запятую: числа от 1 до 168.";return}
            let port=tunnelPort.trimmingCharacters(in:.whitespacesAndNewlines)
            guard port.isEmpty || (Int(port).map{(1...65535).contains($0)} ?? false) else {issue="Укажите порт от 1 до 65535 или оставьте поле пустым.";return}
            request.merge(["token":token,"workspace":workspace,"codex":codex,"sandbox":sandbox,
                           "meter":Bundle.main.executableURL?.path ?? "",
                           "max_parallel":maxParallel,"reminder_hours":hours,"tunnel_port":Int(port) ?? 0,
                           "permissions":["limits":limits,"reminders":reminders,"window_changes":windowChanges,"codex":action=="begin" ? false:codexRequests]]){_,new in new}
        }
        busy=true
        let payload=request,python=python,directory=directory,bridge=bridge
        Task {
            defer {busy=false}
            do {
                let response=try await Task.detached {try bridge(payload,python,directory)}.value
                if let error=response["error"] as? String {issue=error;return}
                apply(response)
                UserDefaults.standard.set(python,forKey:"telegramPython")
                if action=="begin" || action=="disconnect" {token=""}
                if action=="save" {notice="Настройки сохранены"}
                if action=="pair" && !pendingURL.isEmpty {notice="Подтверждение ещё не получено. Откройте ссылку и нажмите Start в Telegram."}
            } catch {issue=error.localizedDescription}
        }
    }

    private func apply(_ value:[String:Any]) {
        connected=value["connected"] as? Bool ?? false;running=value["running"] as? Bool ?? false
        requestsRunning=value["busy"] as? Bool ?? false
        username=value["username"] as? String ?? "";ownerID=(value["owner_id"] as? NSNumber)?.int64Value ?? 0
        pendingURL=value["pending_url"] as? String ?? ""
        // Pairing keeps the draft settings until the new owner confirms.
        guard pendingURL.isEmpty else{return}
        workspace=value["workspace"] as? String ?? "";codex=value["codex"] as? String ?? ""
        sandbox=value["sandbox"] as? String ?? "read-only"
        let permissions=value["permissions"] as? [String:Bool] ?? [:]
        limits=permissions["limits"] ?? true;reminders=permissions["reminders"] ?? true
        windowChanges=permissions["window_changes"] ?? true;codexRequests=permissions["codex"] ?? false
        maxParallel=value["max_parallel"] as? Int ?? 3
        reminderHours=(value["reminder_hours"] as? [Int] ?? [48,24,6]).map(String.init).joined(separator:", ")
        let port=value["tunnel_port"] as? Int ?? 0;tunnelPort=port==0 ? "":String(port)
    }

    nonisolated static func invoke(_ request:[String:Any],_ selectedPython:String,_ directory:URL)throws->[String:Any] {
        guard let resources=Bundle.main.resourceURL else {throw MeterError("Не найдены файлы Telegram-модуля.")}
        let script=resources.appendingPathComponent("Telegram/control.py")
        guard FileManager.default.fileExists(atPath:script.path) else {throw MeterError("Telegram-модуль отсутствует в сборке приложения.")}
        let python=try pythonExecutable(selectedPython)
        let process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=URL(fileURLWithPath:python)
        process.arguments=[script.path,"--directory",directory.path]
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        var environment=ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"]="1"
        environment["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"+(environment["PATH"] ?? "")
        process.environment=environment
        try process.run()
        let watchdog=DispatchWorkItem {if process.isRunning {process.terminate()}}
        DispatchQueue.global().asyncAfter(deadline:.now()+100,execute:watchdog)
        defer {watchdog.cancel()}
        do {try input.fileHandleForWriting.write(contentsOf:JSONSerialization.data(withJSONObject:request));try input.fileHandleForWriting.close()}
        catch {process.terminate();throw MeterError("Не удалось передать настройки Telegram.")}
        let data=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0,let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {
            throw MeterError("Telegram-модуль не ответил. Проверьте Python и доступ к сети.")
        }
        return result
    }

    nonisolated private static func pythonExecutable(_ selected:String)throws->String {
        var candidates=[selected]
        let agent=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.codex-meter.telegram.plist")
        if selected.isEmpty,let data=try? Data(contentsOf:agent),let plist=(try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],let old=(plist["ProgramArguments"] as? [String])?.first {candidates.append(old)}
        if selected.isEmpty {candidates += ["/opt/homebrew/bin/python3","/usr/local/bin/python3","/usr/bin/python3"]}
        for path in candidates where !path.isEmpty && FileManager.default.isExecutableFile(atPath:path) {
            let process=Process();process.executableURL=URL(fileURLWithPath:path)
            process.arguments=["-c","import sys;sys.exit(0 if sys.version_info >= (3,10) else 1)"]
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run()
            let watchdog=DispatchWorkItem {if process.isRunning {process.terminate()}}
            DispatchQueue.global().asyncAfter(deadline:.now()+5,execute:watchdog)
            process.waitUntilExit();watchdog.cancel()
            if process.terminationStatus==0 {return path}
        }
        throw MeterError("Для Telegram нужен Python 3.10 или новее. Установите его с python.org и выберите исполняемый файл в дополнительных настройках.")
    }
}

struct TelegramSettingsCard:View {
    @StateObject private var model:TelegramSettings
    @State private var advanced=false
    @State private var replacement=false
    @State private var confirmation=""
    @MainActor init(model:TelegramSettings?=nil) {_model=StateObject(wrappedValue:model ?? TelegramSettings())}
    var body:some View {
        Card {
            Label("Telegram",systemImage:"paperplane").font(.headline)
            Text("Личный бот и отдельная фоновая служба на этом Mac. Общего получателя сообщений нет.")
                .font(.callout).fixedSize(horizontal:false,vertical:true)
            if model.connected {
                Label(model.running ? "Модуль включён":"Модуль выключен",systemImage:model.running ? "checkmark.circle.fill":"pause.circle")
                    .foregroundStyle(model.running ? MeterTheme.success:MeterTheme.secondary).accessibilityIdentifier("telegram-status")
                Text((model.username.isEmpty ? "Подключённый бот":"@"+model.username)+" · владелец \(model.ownerID)").font(.caption)
                HStack {
                    Button(model.running ? "Выключить":"Включить") {
                        if model.running {confirmation="stop"} else {model.perform("start")}
                    }.accessibilityIdentifier("telegram-enable")
                    Button("Обновить состояние"){model.perform("status")}
                    Button("Отключить привязку…",role:.destructive){confirmation="disconnect"}.accessibilityIdentifier("telegram-disconnect")
                }
                if model.requestsRunning {Text("В боте выполняются запросы. Перед изменением настроек дождитесь их завершения или выключите модуль.").font(.caption).foregroundStyle(MeterTheme.warning)}
            }
            if !model.pendingURL.isEmpty,let url=URL(string:model.pendingURL) {
                Text("Откройте одноразовую ссылку своим аккаунтом и нажмите Start / Запустить. Ссылка действует 10 минут; не пересылайте её.").font(.callout)
                Link("Открыть своего бота в Telegram",destination:url).accessibilityIdentifier("telegram-pair-link")
                HStack {
                    Button("Я нажал Start — проверить"){model.perform("pair")}.accessibilityIdentifier("telegram-pair-check")
                    Button("Отменить подключение"){model.perform("cancel")}
                }
            } else {
                Toggle("Отвечать о квоте по команде /limits",isOn:$model.limits).accessibilityIdentifier("telegram-permission-limits")
                Toggle("Напоминать перед восстановлением квоты",isOn:$model.reminders).accessibilityIdentifier("telegram-permission-reminders")
                Toggle("Сообщать об изменении окна квоты",isOn:$model.windowChanges).accessibilityIdentifier("telegram-permission-window")
                Text("Отключённые категории не отправляются, в том числе из очереди. Платежи и история задач автоматически не пересылаются.")
                    .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                if model.codexRequests {
                    Text("У этого бота отдельно настроены запросы Codex. Их существующие разрешения сохраняются; стандартный модуль уведомлений их не включает.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                }
                DisclosureGroup("Дополнительные настройки",isExpanded:$advanced) {
                    VStack(alignment:.leading,spacing:10) {
                        TextField("Напоминать за часы, через запятую",text:$model.reminderHours).textFieldStyle(.roundedBorder)
                        Text("Часы до восстановления, например 48, 24, 6. Предварительный срок сервера не запускает напоминания.").font(.caption)
                        TextField("Порт локального SSH-туннеля (необязательно)",text:$model.tunnelPort).textFieldStyle(.roundedBorder)
                        Text("Пустое поле — прямой HTTPS. Для туннеля сначала настройте SSH к своему VPS; укажите локальный порт до api.telegram.org:443. Прокси внутри Telegram не применяется к боту.").font(.caption).fixedSize(horizontal:false,vertical:true)
                        HStack {TextField("Python 3.10+ (автоматический поиск)",text:$model.python).textFieldStyle(.roundedBorder);Button("Выбрать Python…"){choose(directory:false){model.python=$0}}}
                        if model.connected {Toggle("Подключить другого бота",isOn:$replacement)}
                    }.padding(.top,8)
                }
                if !model.connected || replacement {
                    Link("Создать своего бота в BotFather",destination:URL(string:"https://t.me/BotFather")!)
                    SecureField("Токен своего бота",text:$model.token).textFieldStyle(.roundedBorder).accessibilityIdentifier("telegram-token")
                    Text("Токен хранится только в приватной папке этого пользователя Mac. Новый бот привязывается только после вашего Start. Прежние диалоги не отправляются новому боту.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Button("Подключить бота"){model.perform("begin")}.disabled(model.token.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("telegram-connect")
                } else {
                    Button("Сохранить настройки Telegram"){model.perform("save")}.accessibilityIdentifier("telegram-save")
                }
            }
            Text("Mac должен быть включён и не спать. Настройки Telegram независимы от системных уведомлений приложения.")
                .font(.caption).foregroundStyle(MeterTheme.secondary)
            if let notice=model.notice {Text(notice).font(.caption).foregroundStyle(MeterTheme.success)}
            if let issue=model.issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.danger).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("telegram-error")}
            if model.busy {ProgressView("Применяем настройки Telegram…").controlSize(.small).accessibilityIdentifier("telegram-progress")}
        }.disabled(model.busy)
        .task {model.perform("status")}
        .onChange(of:model.pendingURL){old,new in if !old.isEmpty && new.isEmpty {replacement=false}}
        .alert(confirmation=="disconnect" ? "Отключить привязку бота?":"Выключить Telegram-модуль?",isPresented:Binding(get:{!confirmation.isEmpty},set:{if !$0 {confirmation=""}})) {
            Button("Отмена",role:.cancel){confirmation=""}
            Button(confirmation=="disconnect" ? "Отключить":"Выключить",role:.destructive){let action=confirmation;confirmation="";model.perform(action)}
        } message:{Text("Выполняющиеся запросы будут остановлены. Уже сделанные изменения файлов не откатываются. При отключении привязки новый получатель не получит прежнюю очередь ответов.")}
    }
    private func choose(directory:Bool,selected:(String)->Void) {
        let panel=NSOpenPanel();panel.canChooseDirectories=directory;panel.canChooseFiles = !directory;panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url {selected(url.path)}
    }
}
