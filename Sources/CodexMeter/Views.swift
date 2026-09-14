import SwiftUI
import Charts
import MeterCore

struct MeterApp:App {
    @StateObject private var store=MeterStore()
    var body:some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU"))
        } label: {
            HStack(spacing:4) {
                Image(systemName:store.snapshot?.fresh()==true ? "gauge.with.dots.needle.50percent":"gauge.with.dots.needle.0percent")
                Text(store.remaining.map{"\(Int($0))%"} ?? "—").monospacedDigit()
                if store.snapshot?.fresh() != true {Image(systemName:"clock")}
                if store.updates.availableVersion != nil {Image(systemName:"arrow.down.circle.fill").foregroundStyle(.mint)}
            }
        }.menuBarExtraStyle(.window)
        Window("Codex Meter",id:"dashboard") {
            DashboardView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU"))
        }.defaultSize(width:980,height:740)
    }
}

struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {VStack(alignment:.leading,spacing:12){content}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:16))}
}
struct Metric:View {
    var label:String;var value:String;var tint:Color = .primary
    var body:some View {VStack(alignment:.leading,spacing:5){Text(label).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)}
}

struct PopoverView:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.openWindow) var openWindow
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Image(systemName:"circle.hexagongrid.fill").foregroundStyle(.mint)
                Text("Codex Meter").font(.headline)
                Spacer()
                if store.updating {ProgressView().controlSize(.small)}
                Button {store.refresh()} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).help("Обновить")
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if let snapshot=store.snapshot,let main=snapshot.main {
                        HStack(spacing:20) {
                            ZStack {
                                Circle().stroke(.quaternary,lineWidth:9)
                                Circle().trim(from:0,to:(store.remaining ?? 0)/100).stroke(Format.color(store.remaining),style:StrokeStyle(lineWidth:9,lineCap:.round)).rotationEffect(.degrees(-90))
                                VStack(spacing:1){Text(store.remaining.map{"\(Int($0))%"} ?? "—").font(.system(size:28,weight:.semibold,design:.rounded)).monospacedDigit();Text("осталось").font(.caption).foregroundStyle(.secondary)}
                            }.frame(width:108,height:108).padding(5)
                            VStack(alignment:.leading,spacing:8) {
                                Text("Запас для работы").font(.title3.weight(.semibold))
                                Text(snapshot.fresh() ? "Квота подписки Codex":"Данные требуют обновления").font(.callout).foregroundStyle(.secondary)
                                Label(snapshot.fetchedAt.formatted(date:.omitted,time:.shortened),systemImage:snapshot.fresh() ? "checkmark.circle":"clock").font(.caption).foregroundStyle(snapshot.fresh() ? Color.secondary:Color.orange)
                            }
                        }.padding(.vertical,5)
                        ForEach(Array(main.windows.enumerated()),id:\.offset) { _,window in QuotaRow(window:window) }
                        if snapshot.buckets.count>1 {
                            DisclosureGroup("Другие лимиты") {
                                ForEach(snapshot.buckets.filter{$0.id != "codex"}) { bucket in
                                    VStack(alignment:.leading,spacing:8){Text(bucket.title).font(.caption.weight(.semibold));ForEach(Array(bucket.windows.enumerated()),id:\.offset){_,w in QuotaRow(window:w)}}.padding(.top,8)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        MoneyCard(compact:true)
                    } else {
                        ContentUnavailableView("Подключаем Codex",systemImage:"gauge.with.dots.needle.0percent",description:Text("Войдите в установленное приложение Codex через подписку ChatGPT."))
                    }
                    if let error=store.error {ErrorBanner(message:error)}
                    if let active=store.tasks.first(where:{$0.task.status=="active"}) {
                        Card {
                            Label("В работе",systemImage:"bolt.fill").font(.caption).foregroundStyle(.mint)
                            Text(active.task.title).font(.callout.weight(.medium)).lineLimit(2)
                            HStack{Text(Format.tokens(active.tokens.total)+" токенов");Spacer();Text(Format.time(active.activeSeconds))}.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(18)
            }.frame(maxHeight:560)
            if let version=store.updates.availableVersion {
                Button {store.updates.check()} label:{Label("Доступна версия \(version)",systemImage:"arrow.down.circle.fill").frame(maxWidth:.infinity,alignment:.leading)}
                    .buttonStyle(.plain).foregroundStyle(.mint).padding(.horizontal,18).padding(.vertical,8)
            }
            Divider()
            HStack {
                Button("Статистика и задачи") {store.tab="tasks";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}}.buttonStyle(.borderedProminent).tint(.mint)
                Spacer()
                Button {store.tab="settings";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}} label:{Image(systemName:"gearshape").frame(width:28,height:28)}.buttonStyle(.plain).help("Настройки").accessibilityLabel("Настройки")
                Menu {Button("Проверить обновления…",action:store.updates.check).disabled(!store.updates.canCheck);Divider();Button("Завершить Codex Meter"){NSApplication.shared.terminate(nil)}} label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width:28,height:28).help("Другие действия").accessibilityLabel("Другие действия")
            }.padding(14)
        }.frame(width:420,height:store.snapshot==nil ? 440:(store.tasks.contains{$0.task.status=="active"} ? 660:550))
        .textSelection(.enabled).background(WindowReader(role:.popover))
    }
}

struct MoneyCard:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.openWindow) var openWindow
    var compact=false
    var body:some View {
        Card {
            HStack{Label("Ресурс в рублях",systemImage:"rublesign.circle").font(.callout.weight(.medium));Spacer();Text("оценка").font(.caption2).foregroundStyle(.secondary)}
            if let money=store.money,let bill=store.currentPayment {
                HStack(spacing:12){Metric(label:"Доступно сейчас",value:Format.rub(money.current),tint:.mint);Metric(label:"Будущие восстановления",value:Format.rub(money.future))}
                if !compact {Text("Всего ещё можно использовать: \(Format.rub(money.current+money.future)) из оплаченных \(Format.rub(bill.amount)).").font(.callout)}
                Text("Доля оплаченной квоты. Будущие окна рассчитаны при сохранении текущих условий; это не денежный баланс.").font(.caption2).foregroundStyle(.secondary)
            } else if store.currentPayment==nil {
                Text("Внесите фактический платёж за подписку, чтобы видеть стоимость доступной квоты и задач.").font(.caption).foregroundStyle(.secondary)
                Button("Добавить платёж") {store.tab="payments";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}}
            } else {Text("Расчёт появится после обновления квоты.").font(.caption).foregroundStyle(.secondary)}
        }
    }
}

struct DashboardView:View {
    @EnvironmentObject var store:MeterStore
    var body:some View {
        VStack(spacing:0) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:4){Text("Codex Meter").font(.largeTitle.weight(.semibold));Text("Понимай расход. Планируй следующие задачи.").foregroundStyle(.secondary)}
                Spacer()
                if let remaining=store.remaining {Text("\(Int(remaining))% осталось").font(.headline).foregroundStyle(Format.color(remaining)).padding(10).background(.quaternary,in:Capsule())}
                Button{store.refresh();store.reloadLocal()}label:{Image(systemName:"arrow.clockwise")}.disabled(store.updating)
            }.padding(24)
            Picker("Раздел",selection:$store.tab){Text("Задачи").tag("tasks");Text("История").tag("history");Text("Платежи").tag("payments");Text("Настройки").tag("settings")}.pickerStyle(.segmented).labelsHidden().padding(.horizontal,24).padding(.bottom,16)
            Divider()
            if let error=store.error {ErrorBanner(message:error,dismiss:{store.error=nil}).padding(10).background(.orange.opacity(0.07))}
            Group {
                switch store.tab {
                case "history":HistoryView()
                case "payments":PaymentsView()
                case "settings":SettingsView()
                default:TasksView()
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:840,minHeight:620)
        .textSelection(.enabled).background(WindowReader(role:.dashboard))
    }
}

struct RunSearchRequest:Equatable {
    var query:String
    var unassigned:Bool
    var service:Bool
    var showRuns:Bool
    var revision:Int
}

struct TasksView:View {
    @EnvironmentObject var store:MeterStore
    @State private var selected:String?=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_TASK"]
    @State private var filter=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_SEARCH"] ?? ""
    @State private var editing:WorkTask?
    @State private var assigning:RunRecord?
    @State private var showUnassigned=false
    @State private var mergeTarget=""
    @State private var taskSort:TaskSort = .recent
    @State private var taskAscending=false
    @State private var taskStatus=""
    @State private var taskKind=""
    @State private var selectedRun:String?=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_RUN"]
    @State private var onlyUnassigned=true
    @State private var includeService=false
    @State private var limit=100
    @State private var searchMatches=Set<String>()
    @State private var searching=false
    @State private var unavailable=0
    @State private var initialized=false
    @State private var searchRevision=0
    var candidates:[RunRecord] {store.runs.filter{(!onlyUnassigned || $0.taskID==nil) && (includeService || !$0.isService)}}
    var filteredRuns:[RunRecord] {candidates.filter{run in filter.isEmpty || [run.title,run.preview ?? "",run.workingDirectory ?? "",run.model,store.tasks.first(where:{$0.id==run.taskID})?.task.title ?? ""].contains(where:{$0.localizedCaseInsensitiveContains(filter)}) || searchMatches.contains(run.id)}}
    var runGroups:[(Date,[RunRecord])] {
        Dictionary(grouping:Array(filteredRuns.prefix(limit)),by:{Calendar.current.startOfDay(for:$0.started)}).sorted{$0.key>$1.key}.map{($0.key,$0.value)}
    }
    var visibleTasks:[TaskSummary] {TaskListQuery.apply(store.tasks,query:filter,status:taskStatus,kind:taskKind,sort:taskSort,ascending:taskAscending)}
    var selectedTask:TaskSummary? {store.tasks.first{$0.id==selected}}
    var body:some View {
        HSplitView {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    TextField(showUnassigned ? "Поиск по запросам и ответам":"Поиск задачи или типа",text:$filter).textFieldStyle(.roundedBorder)
                    Button{editing=WorkTask(title:"",kind:"Произвольная задача")}label:{Image(systemName:"plus")}.help("Создать задачу")
                }
                Picker("Список",selection:$showUnassigned){Text("Задачи").tag(false);Text("Запуски").tag(true)}.pickerStyle(.segmented).labelsHidden()
                if store.loadingHistory {ProgressView("Обновляем историю…").controlSize(.small)}
                if showUnassigned {
                    HStack {
                        Toggle("Без задачи",isOn:$onlyUnassigned)
                        Spacer()
                        Toggle("Служебные",isOn:$includeService)
                    }.toggleStyle(.checkbox).font(.caption)
                    HStack(spacing:6) {
                        if searching {ProgressView().controlSize(.mini);Text("Ищем в переписке…")}
                        else if !filter.isEmpty {Text("Поиск по запросам и ответам")}
                        Spacer()
                        if !filter.isEmpty {Button {searchRevision += 1} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).help("Обновить поиск с учётом новых сообщений").disabled(searching)}
                    }.font(.caption2).foregroundStyle(.secondary).frame(height:16)
                    if unavailable>0 && !filter.isEmpty {Text("Часть журналов недоступна; поиск по ним ограничен заголовками.").font(.caption2).foregroundStyle(.secondary)}
                    List(selection:$selectedRun) {
                        ForEach(runGroups,id:\.0) {date,runs in
                            Section(date.formatted(date:.abbreviated,time:.omitted)) {
                                ForEach(runs) {run in
                                    RunListRow(run:run,taskTitle:store.tasks.first{$0.id==run.taskID}?.task.title).tag(run.id)
                                }
                            }
                        }
                        if filteredRuns.count>limit {Button("Показать ещё 100"){limit += 100}.buttonStyle(.plain)}
                    }.listStyle(.inset).frame(minHeight:220,maxHeight:.infinity)
                    .overlay {
                        if filteredRuns.isEmpty && !searching {
                            VStack(spacing:8) {
                                Image(systemName:"magnifyingglass").font(.title2)
                                Text(filter.isEmpty ? "Нет запусков с этими фильтрами":"Ничего не найдено").font(.callout.weight(.medium))
                                Text("Измените поиск или фильтры выше.").font(.caption)
                            }.foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12).allowsHitTesting(false)
                        }
                    }
                    HStack{Text("Найдено: \(filteredRuns.count)");Spacer();if !includeService {Text("Служебные скрыты")}}.font(.caption2).foregroundStyle(.secondary)
                } else {
                    TaskListControls(sort:$taskSort,ascending:$taskAscending,status:$taskStatus,kind:$taskKind)
                    List(selection:$selected) {
                        ForEach(visibleTasks) {summary in
                            VStack(alignment:.leading,spacing:6) {
                                Text(summary.task.title).font(.callout.weight(.medium)).lineLimit(2)
                                HStack{Text(summary.task.kind).lineLimit(1);Spacer();Text(Format.status(summary.task.status))}.font(.caption2).foregroundStyle(.secondary)
                                HStack{Text(Format.tokens(summary.tokens.total));Text("·");Text(Format.time(summary.activeSeconds));Spacer();Text(summary.rubles.map{Format.rub($0)} ?? summary.measuredRubles.map{Format.rub($0)+" учтено"} ?? "Нет оценки")}.font(.caption).monospacedDigit()
                            }.padding(.vertical,6).textSelection(.disabled).tag(summary.id)
                        }
                    }.listStyle(.inset).frame(minHeight:220,maxHeight:.infinity).accessibilityIdentifier("task-list")
                    .overlay {
                        if visibleTasks.isEmpty {
                            VStack(spacing:8) {
                                Text("Задачи не найдены").font(.headline)
                                Button("Сбросить поиск и фильтры") {filter="";taskStatus="";taskKind=""}.accessibilityIdentifier("task-list-reset")
                            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                        }
                    }
                    HStack {
                        Text("Найдено: \(visibleTasks.count) из \(store.tasks.count)")
                        Spacer()
                        if !taskStatus.isEmpty || !taskKind.isEmpty {
                            Button("Сбросить фильтры") {taskStatus="";taskKind=""}.buttonStyle(.plain)
                        }
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                Text(showUnassigned ? "Выберите запуск, прочитайте переписку и назначьте задачу.":"Одна задача может включать несколько запусков. Откройте «Запуски», чтобы добавить переписку.").font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(minWidth:310,idealWidth:350,maxWidth:420,maxHeight:.infinity,alignment:.top)
            Group {
            if showUnassigned {
                if let run=store.runs.first(where:{$0.id==selectedRun}) {
                    RunDetailView(run:run,assign:{assigning=run}).id(run.id)
                } else {
                    ContentUnavailableView("Выберите запуск",systemImage:"bubble.left.and.bubble.right",description:Text("Справа появятся ваши запросы, ответы Codex и контекст переписки. После просмотра запуск можно назначить задаче."))
                }
            } else if selectedTask == nil {
                TaskEmptyState()
            } else {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if let s=selectedTask {
                        HStack(alignment:.top){VStack(alignment:.leading,spacing:6){Text(s.task.title).font(.title2.weight(.semibold));Text(s.task.kind).foregroundStyle(.secondary)};Spacer();Button{editing=s.task}label:{Image(systemName:"pencil")}}
                        Card {
                            HStack{Metric(label:"Токены",value:Format.tokens(s.tokens.total));Metric(label:"Время выполнения",value:Format.time(s.activeSeconds))}
                            Divider()
                            TaskQuotaView(summary:s)
                            Divider()
                            TaskCostView(summary:s)
                            if s.weeklyQuota==nil || s.quotaQuality.localizedCaseInsensitiveContains("параллельный") {
                                Text(s.quotaQuality).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            }
                        }
                        Grid(alignment:.leading,horizontalSpacing:25,verticalSpacing:10) {
                            detail("Вход",Format.tokens(s.tokens.input));detail("Из него кэш",Format.tokens(s.tokens.cached));detail("Выход",Format.tokens(s.tokens.output));detail("Из него reasoning",Format.tokens(s.tokens.reasoning));detail("Полное время",Format.time(s.wallSeconds));detail("Модели",s.models.joined(separator:", "));detail("Запусков",String(s.runs.count))
                        }.font(.callout)
                        Text("Кэш входит во входные токены, reasoning — в выходные. Полное время включает паузы; время выполнения учитывает параллельную работу один раз.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(s.task.status=="completed" ? "Открыть заново":"Завершить") {var task=s.task;task.status=task.status=="completed" ? "active":"completed";task.finished=task.status=="completed" ? Date():nil;save(task)}
                            if s.task.status != "cancelled" {Button("Отменить задачу"){var task=s.task;task.status="cancelled";task.finished=Date();save(task)}}
                        }
                        if store.tasks.count>1 {
                            DisclosureGroup("Объединить с другой задачей") {
                                VStack(alignment:.leading,spacing:10) {
                                    TaskChooser(choices:TaskChoice.sorted(store.tasks,excluding:s.id),selection:$mergeTarget)
                                    Button("Объединить"){do{try store.merge(s.id,mergeTarget);selected=mergeTarget;mergeTarget=""}catch{store.error=error.localizedDescription}}.disabled(mergeTarget.isEmpty)
                                }.padding(.top,8)
                            }.font(.caption)
                        }
                        if !s.runs.isEmpty {
                            Text("Переписка задачи").font(.headline)
                            ForEach(s.runs.sorted{$0.started<$1.started}) {run in
                                Button {selectedRun=run.id;onlyUnassigned=false;showUnassigned=true} label: {
                                    HStack{Text(run.title).lineLimit(2);Spacer();Image(systemName:"chevron.right")}
                                }.buttonStyle(.bordered)
                            }
                        }
                        ForecastCard(forecast:store.forecast(s.task.kind))
                    }
                }.padding(22)
            }
            }
            }.frame(minWidth:420,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
        .onAppear {if !initialized {initialized=true;showUnassigned=store.tasks.isEmpty}}
        .onChange(of:filter){_,_ in limit=100;searchMatches=[]}
        .onChange(of:selected){_,_ in DispatchQueue.main.async { mergeTarget="" }}
        .onChange(of:visibleTasks.map(\.id)) {_,ids in
            if let selected,!ids.contains(selected) {DispatchQueue.main.async { self.selected=nil }}
        }
        .task(id:RunSearchRequest(query:filter,unassigned:onlyUnassigned,service:includeService,showRuns:showUnassigned,revision:searchRevision)) {
            unavailable=0;searching=false
            guard showUnassigned,!filter.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
            searching=true
            do {
                try await Task.sleep(for:.milliseconds(300))
                let result=try await TranscriptRepository.shared.search(filter,runs:candidates)
                try Task.checkCancellation();searchMatches=result.matches;unavailable=result.unavailable;searching=false
            } catch is CancellationError {} catch {searching=false}
        }
        .sheet(item:$editing){task in TaskEditor(task:task){save($0)}}
        .sheet(item:$assigning){run in AssignEditor(run:run)}
    }
    func detail(_ label:String,_ value:String) -> some View {GridRow{Text(label).foregroundStyle(.secondary);Text(value).textSelection(.enabled)}}
    func save(_ task:WorkTask){do{try store.saveTask(task)}catch{store.error=error.localizedDescription}}
}

struct TaskEmptyState:View {
    @EnvironmentObject var store:MeterStore
    var body:some View {
        GeometryReader {geometry in
            ScrollView {
                VStack(spacing:24) {
                    Spacer(minLength:16)
                    VStack(spacing:14) {
                        Image(systemName:"square.stack.3d.up")
                            .font(.system(size:38,weight:.light)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text("Выберите задачу").font(.title2.weight(.semibold))
                        Text("Откройте задачу слева, чтобы увидеть расход токенов, время, стоимость и долю недельной квоты.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal:false,vertical:true)
                        if !store.integrationInstalled {
                            Button("Подключить учёт к Codex"){store.tab="settings"}
                        }
                    }.multilineTextAlignment(.center).frame(maxWidth:380)
                        .frame(maxWidth:.infinity).accessibilityIdentifier("task-empty-message")
                    Spacer(minLength:16)
                    MoneyCard().frame(maxWidth:640).frame(maxWidth:.infinity)
                }.padding(24).frame(maxWidth:.infinity,minHeight:geometry.size.height)
            }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct ForecastCard:View {
    var forecast:Forecast
    var body:some View {
        Card {
            Label("Следующая похожая задача",systemImage:"sparkle.magnifyingglass").font(.headline)
            Text("История: \(forecast.samples) завершённых задач").font(.caption).foregroundStyle(.secondary)
            if let tokens=forecast.tokenMedian {HStack{Metric(label:"Обычно токенов",value:Format.tokens(Int64(tokens)));Metric(label:"С запасом",value:forecast.tokenUpper.map{Format.tokens(Int64($0))} ?? "—")}}
            if let seconds=forecast.secondsMedian {Text("Обычно занимает \(Format.time(seconds))").font(.callout)}
            Text(forecast.explanation).font(.caption).foregroundStyle(forecast.risk=="high" ? .red:forecast.risk=="caution" ? .orange:.secondary)
        }
    }
}

struct TaskEditor:View {
    @Environment(\.dismiss) var dismiss
    @State var task:WorkTask
    var save:(WorkTask)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:18){Text("Пользовательская задача").font(.title2);TextField("Конкретный результат: ревью API заказов",text:$task.title);TextField("Тип задачи: code-review",text:$task.kind);Text("Тип объединяет повторяющиеся задачи для прогноза. Конкретное название отличает один запуск от другого.").font(.caption).foregroundStyle(.secondary);HStack{Button("Отмена"){dismiss()};Spacer();Button("Сохранить"){save(task);dismiss()}.buttonStyle(.borderedProminent).disabled(task.title.trimmingCharacters(in:.whitespaces).isEmpty || task.kind.trimmingCharacters(in:.whitespaces).isEmpty)}}.textFieldStyle(.roundedBorder).padding(24).frame(width:480)
    }
}

struct AssignEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    var run:RunRecord
    @State private var target=""
    @State private var title=""
    @State private var kind="Произвольная задача"
    @State private var creating=false
    @State private var issue:String?
    private var cleanTitle:String {title.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var cleanKind:String {kind.trimmingCharacters(in:.whitespacesAndNewlines)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Добавить к задаче").font(.title2)
            Text("Выберите результат, к которому относится этот запрос.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:6) {
                Text("Выбранный запрос").font(.caption.weight(.semibold))
                Text(run.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
            if !store.tasks.isEmpty {
                Picker("Куда добавить",selection:$creating) {
                    Text("В существующую задачу").tag(false)
                    Text("Создать задачу").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            if creating || store.tasks.isEmpty {
                VStack(alignment:.leading,spacing:6) {
                    Text("Название задачи").font(.callout.weight(.medium))
                    TextField("Какой результат объединяет эти запросы?",text:$title)
                        .accessibilityIdentifier("assignment-title")
                    Text("Например: Разработка Codex Meter или Ревью API заказов.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading,spacing:6) {
                    Text("Тип для сравнения похожих задач").font(.callout.weight(.medium))
                    TextField("Произвольная задача",text:$kind)
                    Text("Для прогноза расхода. Можно оставить «Произвольная задача»; для повторяющейся работы указывайте один тип, например code-review.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            } else {
                TaskChooser(choices:TaskChoice.sorted(store.tasks),selection:$target,autofocus:true,confirm:addToTask)
                Text("Запрос дополнит историю, токены и время выбранной задачи. Остальная переписка не переносится.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if let issue {Text(issue).font(.caption).foregroundStyle(.red)}
            HStack {
                Button("Отмена"){dismiss()}
                Spacer()
                Button(creating || store.tasks.isEmpty ? "Создать и добавить":"Добавить к задаче") {
                    addToTask()
                }.buttonStyle(.borderedProminent)
                .disabled(creating || store.tasks.isEmpty ? cleanTitle.isEmpty:!store.tasks.contains(where:{$0.id==target}))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("assignment-save")
            }
        }.textFieldStyle(.roundedBorder).padding(20).frame(width:580)
        .onAppear{target=run.taskID ?? "";creating=store.tasks.isEmpty}
    }
    private func addToTask() {
        let task:WorkTask
        if creating || store.tasks.isEmpty {
            guard !cleanTitle.isEmpty else { return }
            task=WorkTask(title:cleanTitle,kind:cleanKind.isEmpty ? "Произвольная задача":cleanKind,status:"paused",created:run.started)
        } else {
            guard let existing=store.tasks.first(where:{$0.id==target})?.task else { return }
            task=existing
        }
        do { try store.assign(run,to:task);dismiss() } catch { issue=error.localizedDescription }
    }
}

struct HistoryView:View {
    @EnvironmentObject var store:MeterStore
    @State private var days=30
    var buckets:[DailyUsage] {
        let fmt=DateFormatter();fmt.dateFormat="yyyy-MM-dd";fmt.locale=Locale(identifier:"en_US_POSIX")
        let cutoff=fmt.string(from:Calendar.current.date(byAdding:.day,value:-days,to:Date())!)
        return (store.snapshot?.daily ?? []).filter{$0.startDate>=cutoff}
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack{Text("История расхода").font(.title2.weight(.semibold));Spacer();Picker("Период",selection:$days){Text("7 дней").tag(7);Text("30 дней").tag(30);Text("90 дней").tag(90)}.pickerStyle(.segmented).labelsHidden().frame(width:260)}
                HStack{Metric(label:"Токены в доступных записях",value:Format.tokens(buckets.reduce(0){$0+$1.tokens}));Metric(label:"Последняя запись сервера",value:store.snapshot?.daily?.last?.startDate ?? "—");Metric(label:"Учтено локальных задач",value:String(store.tasks.count))}
                if buckets.isEmpty {ContentUnavailableView("Нет дневных записей",systemImage:"chart.bar",description:Text("Сервис может возвращать историю с задержкой. Отсутствующая запись не означает нулевой расход."))}
                else {
                    Chart(buckets){bucket in
                        if let date=ISO8601DateFormatter().date(from:bucket.startDate+"T12:00:00Z") {
                            BarMark(x:.value("Дата",date,unit:.day),y:.value("Токены",bucket.tokens)).foregroundStyle(.mint.gradient).cornerRadius(3)
                        }
                    }
                    .chartXAxis{AxisMarks(values:.stride(by:.day,count:days>30 ? 14:(days>7 ? 5:1))){_ in AxisGridLine();AxisValueLabel(format:.dateTime.day().month(.abbreviated))}}
                    .chartYAxis{AxisMarks(values:.automatic(desiredCount:4)){axis in AxisGridLine();AxisValueLabel{if let count=axis.as(Int64.self){Text(Format.tokens(count))}}}}
                    .frame(height:250)
                    Text("Источник: дневная статистика аккаунта Codex. Показана сумма полученных записей; полнота периода и часовой пояс серверных дней не гарантируются. Локальные данные ниже считаются отдельно.").font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    Text("Сегодня на этом Mac").font(.headline)
                    let count=store.runs.flatMap(\.tokenEvents).filter{Calendar.current.isDateInToday($0.date)}.reduce(Int64(0)){$0+$1.tokens.total}
                    Metric(label:"По локальным событиям · ваш часовой пояс",value:Format.tokens(count)+" токенов")
                    Text("Включает размеченные и неразмеченные задачи. Не прибавляется к статистике аккаунта, чтобы избежать двойного счёта.").font(.caption).foregroundStyle(.secondary)
                }
                MoneyCard()
            }.padding(24)
        }
    }
}

struct PaymentsView:View {
    @EnvironmentObject var store:MeterStore
    @State private var editing:Payment?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack{Text("Фактические платежи").font(.title2.weight(.semibold));Spacer();Button("Добавить платёж"){editing=Payment.nextDraft(after:store.payments)}.buttonStyle(.borderedProminent).accessibilityIdentifier("payment-add")}
                Text("Раз в месяц внесите сумму, которую действительно заплатили в рублях. Дата окончания — начало следующего оплаченного периода.").foregroundStyle(.secondary)
                MoneyCard()
                ForEach(store.payments){payment in
                    Card {
                        HStack{Metric(label:"Оплачено",value:Format.rub(payment.amount));VStack(alignment:.leading){Text(payment.start.formatted(date:.abbreviated,time:.omitted)+" → "+payment.end.formatted(date:.abbreviated,time:.omitted));Text(payment.contains(Date()) ? "Текущий период":"История").font(.caption).foregroundStyle(.secondary)};Button("Изменить"){editing=payment}}
                    }
                }
                Card {
                    Text("Как считаются рубли").font(.headline)
                    Text("Цена задачи = платёж × длительность окна квоты / длительность оплаченного периода × использованная доля окна.").font(.callout)
                    Text("Вся внесённая сумма условно относится к Codex. Неиспользованная квота не увеличивает цену задач. Дополнительные лимиты моделей не суммируются с основной квотой. Смена тарифа или условий требует нового расчёта; приложение не считает процент квоты фиксированным количеством токенов.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.sheet(item:$editing){PaymentEditor(payment:$0)}
    }
}

struct PaymentEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    @State var payment:Payment
    @State private var amount=""
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Оплата подписки").font(.title2)
            TextField("Фактически уплачено, ₽",text:$amount).textFieldStyle(.roundedBorder).accessibilityIdentifier("payment-amount")
            DatePicker("Начало периода",selection:$payment.start,displayedComponents:.date).accessibilityIdentifier("payment-start")
            DatePicker("Следующий платёж",selection:$payment.end,displayedComponents:.date).accessibilityIdentifier("payment-end")
            if let error {Text(error).font(.caption).foregroundStyle(.red)}
            HStack{Button("Отмена"){dismiss()};Spacer();Button("Сохранить"){
                guard let value=Double(amount.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:",",with:".")) else{error="Введите сумму в рублях";return}
                payment.amount=value;payment.start=Calendar.current.startOfDay(for:payment.start);payment.end=Calendar.current.startOfDay(for:payment.end)
                do{try store.savePayment(payment);dismiss()}catch{self.error=error.localizedDescription}
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("payment-save")}
        }.padding(24).frame(width:440).onAppear{amount=payment.amount>0 ? String(payment.amount):""}
    }
}

struct SettingsView:View {
    @EnvironmentObject var store:MeterStore
    @State private var savedAlertSettings:String?
    private var alertSettingsKey:String { "\(store.thresholds)|\(store.expiryReminder)|\(store.expiryDays)|\(store.expiryRemaining)|\(store.lastDayRemaining)" }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("Настройки").font(.title2.weight(.semibold))
                Card {
                    Toggle("Запускать при входе в macOS",isOn:Binding(get:{store.loginEnabled},set:{store.setLogin($0)}))
                    Toggle("Уведомлять о расходе квоты",isOn:Binding(get:{store.notifications},set:{value in Task{await store.enableNotifications(value)}}))
                    if let issue=store.notificationIssue {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                        Button("Открыть Системные настройки") {
                            if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences") {NSWorkspace.shared.open(url)}
                        }
                    }
                    TextField("Пороги расхода, %",text:$store.thresholds).textFieldStyle(.roundedBorder)
                    Text("50% — мягкое предупреждение. 80%, 90%, 95% — осталось 20%, 10%, 5%. Каждый порог срабатывает один раз за окно.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Напоминать о большом остатке перед восстановлением",isOn:$store.expiryReminder)
                    HStack{Stepper("За \(store.expiryDays) дн.",value:$store.expiryDays,in:2...6);Spacer();Stepper("Остаток ≥ \(store.expiryRemaining)%",value:$store.expiryRemaining,in:5...95,step:5)}
                    Stepper("За сутки: остаток ≥ \(store.lastDayRemaining)%",value:$store.lastDayRemaining,in:5...95,step:5)
                    Text("Напоминание использует свежие данные и приходит один раз за недельное окно. После сна проверка выполняется при пробуждении.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Сохранить пороги уведомлений") {
                            do {try store.saveAlertSettings();savedAlertSettings=alertSettingsKey}
                            catch {store.error=error.localizedDescription}
                        }.buttonStyle(.borderedProminent)
                        if savedAlertSettings==alertSettingsKey {Label("Сохранено",systemImage:"checkmark").font(.caption).foregroundStyle(.mint)}
                    }
                }
                SoftwareUpdateCard(updater:store.updates)
                ConnectionCard()
                Card {
                    Label(store.integrationInstalled ? "Учёт задач подключён":"Подключение учёта задач",systemImage:"link").font(.headline)
                    Text("Для скиллов Codex автоматически отмечает начало задачи, проверяет прогноз и сохраняет результат. Для остальной работы: «начинаем задачу …», «продолжаем задачу …», «задача завершена».").font(.callout)
                    Text("Изменения подключения подхватываются в новых сессиях Codex. Начало и завершение смысловой задачи определяет агент; записи можно исправить и объединить в приложении.").font(.caption).foregroundStyle(.secondary)
                    Button("Открыть папку данных"){NSWorkspace.shared.open(Database.defaultDirectory)}
                }
                Text("Данные хранятся на этом Mac в SQLite. Сохраняются счётчики, короткие названия и связи задач; полная переписка не копируется. Формат журналов Codex может меняться — проверяйте свежесть данных после обновлений.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}
