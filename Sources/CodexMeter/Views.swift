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
                if store.updates.availableVersion != nil {Image(systemName:"arrow.down.circle.fill").foregroundStyle(MeterTheme.accent)}
            }
        }.menuBarExtraStyle(.window)
        Window("Codex Meter",id:"dashboard") {
            DashboardView().environmentObject(store).environment(\.locale,Locale(identifier:"ru_RU"))
        }.defaultSize(width:980,height:740)
    }
}

struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {VStack(alignment:.leading,spacing:12){content}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(MeterTheme.surface,in:RoundedRectangle(cornerRadius:16))}
}
struct Metric:View {
    var label:String;var value:String;var tint:Color = .primary
    var body:some View {VStack(alignment:.leading,spacing:5){Text(label).font(.caption).foregroundStyle(MeterTheme.secondary);Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)}
}

struct PopoverView:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.openWindow) var openWindow
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Image(systemName:"circle.hexagongrid.fill").foregroundStyle(MeterTheme.accent)
                Text("Codex Meter").font(.headline)
                Text("v\(store.updates.currentVersion)")
                    .font(.caption.monospacedDigit()).foregroundStyle(MeterTheme.secondary)
                    .help("Установленная версия Codex Meter")
                    .accessibilityLabel("Установленная версия \(store.updates.currentVersion)")
                    .accessibilityIdentifier("installed-version")
                Spacer()
                if store.updating {ProgressView().controlSize(.small)}
                Button {store.refresh()} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).disabled(store.updating).help("Обновить")
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if let snapshot=store.snapshot,let main=snapshot.main {
                        HStack(spacing:20) {
                            ZStack {
                                Circle().stroke(.quaternary,lineWidth:9)
                                Circle().trim(from:0,to:(store.remaining ?? 0)/100).stroke(Format.color(store.remaining),style:StrokeStyle(lineWidth:9,lineCap:.round)).rotationEffect(.degrees(-90))
                                VStack(spacing:1){Text(store.remaining.map{"\(Int($0))%"} ?? "—").font(.system(size:28,weight:.semibold,design:.rounded)).monospacedDigit();Text("осталось").font(.caption).foregroundStyle(MeterTheme.secondary)}
                            }.frame(width:108,height:108).padding(5)
                            VStack(alignment:.leading,spacing:8) {
                                Text("Запас для работы").font(.title3.weight(.semibold))
                                Text(snapshot.fresh() ? "Квота подписки Codex":"Данные требуют обновления").font(.callout).foregroundStyle(MeterTheme.secondary)
                                Label(snapshot.fetchedAt.formatted(date:.omitted,time:.shortened),systemImage:snapshot.fresh() ? "checkmark.circle":"clock").font(.caption).foregroundStyle(snapshot.fresh() ? MeterTheme.secondary:MeterTheme.warning)
                            }
                        }.padding(.vertical,5)
                        ForEach(Array(main.windows.enumerated()),id:\.offset) { _,window in QuotaRow(window:window) }
                        if let change=snapshot.weeklyResetChange {
                            Text("\(change.observedAt.formatted(date:.abbreviated,time:.shortened)): сервер сообщил другую дату недельного сброса. Ранее: \(Date(timeIntervalSince1970:change.previousReset).formatted(date:.abbreviated,time:.shortened)).\(change.usageDropped ? " Расход также снизился. Точный момент сброса между опросами неизвестен.":"")")
                                .font(.caption2).foregroundStyle(MeterTheme.warning)
                        }
                        if snapshot.buckets.count>1 {
                            DisclosureGroup("Другие лимиты") {
                                ForEach(snapshot.buckets.filter{$0.id != "codex"}) { bucket in
                                    VStack(alignment:.leading,spacing:8){Text(bucket.title).font(.caption.weight(.semibold));ForEach(Array(bucket.windows.enumerated()),id:\.offset){_,w in QuotaRow(window:w)}}.padding(.top,8)
                                }
                            }.font(.caption).foregroundStyle(MeterTheme.secondary)
                        }
                        MoneyCard(compact:true)
                    } else {
                        ContentUnavailableView("Подключаем Codex",systemImage:"gauge.with.dots.needle.0percent",description:Text("Войдите в установленное приложение Codex через подписку ChatGPT."))
                    }
                    if let error=store.error {ErrorBanner(message:error)}
                    if let active=store.tasks.first(where:{$0.task.status=="active"}) {
                        Card {
                            Label("В работе",systemImage:"bolt.fill").font(.caption).foregroundStyle(MeterTheme.accent)
                            Text(active.task.title).font(.callout.weight(.medium)).lineLimit(2)
                            HStack{Text(Format.tokens(active.tokens.total)+" токенов");Spacer();Text(Format.time(active.activeSeconds))}.font(.caption).foregroundStyle(MeterTheme.secondary)
                        }
                    }
                }.padding(18)
            }.frame(maxHeight:560)
            if let version=store.updates.availableVersion {
                Button {store.updates.check()} label:{Label("Доступна версия \(version)",systemImage:"arrow.down.circle.fill").frame(maxWidth:.infinity,alignment:.leading)}
                    .buttonStyle(.plain).foregroundStyle(MeterTheme.accent).padding(.horizontal,18).padding(.vertical,8)
            }
            Divider()
            HStack {
                Button("Статистика и задачи") {store.tab="tasks";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}}.buttonStyle(.borderedProminent)
                Spacer()
                Button {store.tab="settings";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}} label:{Image(systemName:"gearshape").frame(width:28,height:28)}.buttonStyle(.plain).help("Настройки").accessibilityLabel("Настройки")
                Menu {Button("Проверить обновления…",action:store.updates.check).disabled(!store.updates.canCheck);Divider();Button("Завершить Codex Meter"){NSApplication.shared.terminate(nil)}} label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width:28,height:28).help("Другие действия").accessibilityLabel("Другие действия")
            }.padding(14)
        }.frame(width:420,height:store.snapshot==nil ? 440:(store.tasks.contains{$0.task.status=="active"} ? 660:550))
        .textSelection(.enabled).background(MeterTheme.background).actionProgress().background(WindowReader(role:.popover))
    }
}

struct MoneyCard:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.openWindow) var openWindow
    var compact=false
    var body:some View {
        Card {
            HStack{Label("Ресурс в рублях",systemImage:"rublesign.circle").font(.callout.weight(.medium));Spacer();Text("оценка").font(.caption2).foregroundStyle(MeterTheme.secondary)}
            if let money=store.money,let bill=store.currentPayment {
                HStack(spacing:12){Metric(label:"Доступно сейчас",value:Format.rub(money.current),tint:MeterTheme.accent);Metric(label:"Будущие восстановления",value:Format.rub(money.future))}
                if !compact {Text("Всего ещё можно использовать: \(Format.rub(money.current+money.future)) из оплаченных \(Format.rub(bill.amount)).").font(.callout)}
                Text("Доля оплаченной квоты. Будущие окна рассчитаны при сохранении текущих условий; это не денежный баланс.").font(.caption2).foregroundStyle(MeterTheme.secondary)
            } else if store.currentPayment==nil {
                Text("Внесите фактический платёж за подписку, чтобы видеть стоимость доступной квоты и задач.").font(.caption).foregroundStyle(MeterTheme.secondary)
                Button("Добавить платёж") {store.tab="payments";WindowNavigation.shared.showDashboard {openWindow(id:"dashboard")}}
            } else {Text("Расчёт появится после обновления квоты.").font(.caption).foregroundStyle(MeterTheme.secondary)}
        }
    }
}

struct DashboardView:View {
    @EnvironmentObject var store:MeterStore
    var body:some View {
        VStack(spacing:0) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:4){Text("Codex Meter").font(.largeTitle.weight(.semibold));Text("Понимай расход. Планируй следующие задачи.").foregroundStyle(MeterTheme.secondary)}
                Spacer()
                if let remaining=store.remaining {Text("\(Int(remaining))% осталось").font(.headline).foregroundStyle(Format.color(remaining)).padding(10).background(.quaternary,in:Capsule())}
                HStack(spacing:8) {
                    if store.updating {ProgressView().controlSize(.small).help("Обновляем квоту…")}
                    Button{store.refresh();store.reloadLocal()}label:{Image(systemName:"arrow.clockwise")}.disabled(store.updating).help("Обновить данные")
                }
            }.padding(24)
            Picker("Раздел",selection:$store.tab){Text("Задачи").tag("tasks");Text("История").tag("history");Text("Платежи").tag("payments");Text("Настройки").tag("settings")}.pickerStyle(.segmented).labelsHidden().padding(.horizontal,24).padding(.bottom,16)
            Divider()
            if let error=store.error {ErrorBanner(message:error,dismiss:{store.error=nil}).padding(10).background(MeterTheme.warning.opacity(0.07))}
            Group {
                switch store.tab {
                case "history":HistoryView()
                case "payments":PaymentsView()
                case "settings":SettingsView()
                default:TasksView()
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:840,minHeight:620)
        .textSelection(.enabled).background(MeterTheme.background).actionProgress().background(WindowReader(role:.dashboard))
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
    @State private var assigning:RunAssignment?
    @State private var checkedRuns=Set<String>()
    @State private var checkedTasks=Set<String>()
    @State private var taskBatch:TaskBatchRequest?
    @State private var previewRun:String?=ProcessInfo.processInfo.environment["CODEX_METER_RENDER_RUN"]
    @State private var showUnassigned=false
    @State private var taskSort:TaskSort = .recent
    @State private var taskAscending=false
    @State private var taskStatus=""
    @State private var taskKind=""
    @State private var runTypeFilter=""
    @State private var runFiltersOpen=false
    @State private var managingTypes=false
    @State private var onlyUnassigned=true
    @State private var includeService=false
    @State private var limit=100
    @State private var searchMatches=Set<String>()
    @State private var searching=false
    @State private var unavailable=0
    @State private var initialized=false
    @State private var searchRevision=0
    var candidates:[RunRecord] {
        let types=Dictionary(uniqueKeysWithValues:store.tasks.compactMap{s in s.task.typeID.map{(s.id,$0)}})
        return store.runs.filter{run in
        let typeID=run.taskID.flatMap{types[$0]}
        return (!onlyUnassigned || run.taskID==nil) && (includeService || !run.isService) && (runTypeFilter.isEmpty || (runTypeFilter=="unclassified" ? typeID==nil:typeID==runTypeFilter))
    }}
    var filteredRuns:[RunRecord] {candidates.filter{run in filter.isEmpty || [run.title,run.preview ?? "",run.workingDirectory ?? "",run.model,store.tasks.first(where:{$0.id==run.taskID})?.task.title ?? ""].contains(where:{$0.localizedCaseInsensitiveContains(filter)}) || searchMatches.contains(run.id)}}
    var shownRuns:[RunRecord] {Array(filteredRuns.prefix(limit))}
    var runGroups:[(Date,[RunRecord])] {
        Dictionary(grouping:shownRuns,by:{Calendar.current.startOfDay(for:$0.started)}).sorted{$0.key>$1.key}.map{($0.key,$0.value)}
    }
    var visibleTasks:[TaskSummary] {TaskListQuery.apply(store.tasks,query:filter,status:taskStatus,kind:taskKind,sort:taskSort,ascending:taskAscending)}
    var tasksToActOn:[TaskSummary] {visibleTasks.filter{checkedTasks.contains($0.id)}}
    var selectedTask:TaskSummary? {store.tasks.first{$0.id==selected}}
    var runsToAssign:[RunRecord] {shownRuns.filter{checkedRuns.contains($0.id)}}
    var body:some View {
        HSplitView {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    TextField(showUnassigned ? "Поиск по запросам и ответам":"Поиск задачи или типа",text:Binding(get:{filter},set:{filter=$0;limit=100})).textFieldStyle(.roundedBorder)
                    Button{editing=WorkTask(title:"",kind:"")}label:{Image(systemName:"plus")}.help("Создать задачу")
                    Button("Типы",systemImage:"tag"){managingTypes=true}.help("Типы задач")
                        .accessibilityIdentifier("task-types-open")
                }
                Picker("Список",selection:$showUnassigned){Text("Задачи").tag(false);Text("Запуски").tag(true)}.pickerStyle(.segmented).labelsHidden()
                if store.loadingHistory {ProgressView("Обновляем историю…").controlSize(.small)}
                if showUnassigned {
                    HStack {
                        Toggle("Без задачи",isOn:$onlyUnassigned)
                        Spacer()
                        Toggle("Служебные",isOn:$includeService)
                        Button {runFiltersOpen.toggle()} label:{Image(systemName:runTypeFilter.isEmpty ? "line.3.horizontal.decrease":"line.3.horizontal.decrease.circle.fill")}
                            .help("Фильтр по типу задачи").accessibilityLabel("Тип задачи запуска").accessibilityIdentifier("run-type-filter-open")
                            .popover(isPresented:$runFiltersOpen) {
                                VStack(alignment:.leading,spacing:12) {
                                    TaskTypeFilter(selection:$runTypeFilter).accessibilityIdentifier("run-type-filter")
                                    Button("Готово"){runFiltersOpen=false}.keyboardShortcut(.defaultAction)
                                }.padding(18).frame(width:280)
                            }
                    }.toggleStyle(.checkbox).font(.caption)
                    HStack(spacing:6) {
                        if searching {ProgressView().controlSize(.mini);Text("Ищем в переписке…")}
                        else if !filter.isEmpty {Text("Поиск по запросам и ответам")}
                        Spacer()
                        if !filter.isEmpty {Button {searchRevision += 1} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).help("Обновить поиск с учётом новых сообщений").disabled(searching)}
                    }.font(.caption2).foregroundStyle(MeterTheme.secondary).frame(height:16)
                    if unavailable>0 && !filter.isEmpty {Text("Часть журналов недоступна; поиск по ним ограничен заголовками.").font(.caption2).foregroundStyle(MeterTheme.secondary)}
                    List(selection:$previewRun) {
                        ForEach(runGroups,id:\.0) {date,runs in
                            Section(date.formatted(date:.abbreviated,time:.omitted)) {
                                ForEach(runs) {run in
                                    HStack {
                                        Button {
                                            if checkedRuns.contains(run.id) {checkedRuns.remove(run.id)} else {checkedRuns.insert(run.id)}
                                        } label: {
                                            ZStack {
                                                RoundedRectangle(cornerRadius:4)
                                                    .fill(checkedRuns.contains(run.id) ? Color(red:0,green:0.32,blue:0.72):MeterTheme.background)
                                                RoundedRectangle(cornerRadius:4)
                                                    .strokeBorder(checkedRuns.contains(run.id) ? Color.white:MeterTheme.secondary,lineWidth:1.5)
                                                if checkedRuns.contains(run.id) {
                                                    Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(.white)
                                                }
                                            }.frame(width:20,height:20)
                                                .frame(width:44,height:44).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                            .accessibilityLabel("Отметить: \(run.title)")
                                            .accessibilityValue(checkedRuns.contains(run.id) ? "Отмечен":"Не отмечен")
                                            .accessibilityIdentifier("run-check-\(run.id)")
                                            .help("Изменить отметку только этого запуска")
                                        VStack(alignment:.leading,spacing:4) {
                                            RunListRow(run:run,taskTitle:store.tasks.first{$0.id==run.taskID}?.task.title)
                                            if store.tasks.first(where:{$0.id==run.taskID})?.task.typeID==nil {
                                                Button {
                                                    if let task=store.tasks.first(where:{$0.id==run.taskID})?.task {editing=task}
                                                    else {assigning=RunAssignment(runs:[run])}
                                                } label:{Label("Нужно указать тип задачи",systemImage:"tag")}
                                                    .buttonStyle(.plain).font(.caption2).foregroundStyle(MeterTheme.warning)
                                                    .accessibilityIdentifier("run-needs-type-\(run.id)")
                                            }
                                        }
                                    }.tag(run.id)
                                }
                            }
                        }
                        if filteredRuns.count>limit {Button("Показать ещё 100"){limit += 100}.buttonStyle(.plain)}
                    }.listStyle(.inset).frame(minHeight:220,maxHeight:.infinity)
                    .onExitCommand {previewRun=nil}
                    .overlay {
                        if filteredRuns.isEmpty && !searching {
                            VStack(spacing:8) {
                                Image(systemName:"magnifyingglass").font(.title2)
                                Text(filter.isEmpty ? "Нет запусков с этими фильтрами":"Ничего не найдено").font(.callout.weight(.medium))
                                Text("Измените поиск или фильтры выше.").font(.caption)
                            }.foregroundStyle(MeterTheme.secondary).multilineTextAlignment(.center).padding(12).allowsHitTesting(false)
                        }
                    }
                    HStack(spacing:8) {
                        Button {
                            checkedRuns=runsToAssign.count==shownRuns.count ? []:Set(shownRuns.map(\.id))
                        } label: {
                            Image(systemName:checkedRuns.isEmpty ? "square":runsToAssign.count==shownRuns.count ? "checkmark.square.fill":"minus.square.fill")
                        }.help("Выбрать или снять выбор показанных запусков (\(shownRuns.count))")
                            .accessibilityLabel("Выбрать показанные запуски").accessibilityIdentifier("run-select-visible")
                            .disabled(shownRuns.isEmpty)
                        Text(checkedRuns.isEmpty ? "Найдено: \(filteredRuns.count)":"Выбрано: \(runsToAssign.count)")
                            .monospacedDigit().accessibilityIdentifier("run-selection-count")
                        Spacer(minLength:0)
                        if !checkedRuns.isEmpty {
                            Button {assigning=RunAssignment(runs:runsToAssign)} label:{Label("Назначить",systemImage:"folder.badge.plus")}
                                .accessibilityIdentifier("run-assign-selected")
                            Button {checkedRuns=[]} label:{Image(systemName:"xmark")}
                                .help("Снять все отметки").accessibilityLabel("Снять выделение")
                                .accessibilityIdentifier("run-clear-selection")
                        }
                    }.font(.caption).controlSize(.small).frame(height:28)
                } else {
                    TaskListControls(sort:$taskSort,ascending:$taskAscending,status:$taskStatus,kind:$taskKind)
                    List(selection:$selected) {
                        ForEach(visibleTasks) {summary in
                            HStack(spacing:4) {
                                TaskCheckButton(title:summary.task.title,id:summary.id,checked:checkedTasks.contains(summary.id)) {
                                    if checkedTasks.contains(summary.id) {checkedTasks.remove(summary.id)} else {checkedTasks.insert(summary.id)}
                                }
                                VStack(alignment:.leading,spacing:6) {
                                    Text(summary.task.title).font(.callout.weight(.medium)).lineLimit(2)
                                    HStack{Text(summary.task.typeLabel).lineLimit(1);Spacer();Text(Format.status(summary.task.status))}.font(.caption2).foregroundStyle(.primary)
                                    HStack{Text(Format.tokens(summary.tokens.total));Text("·");Text(Format.time(summary.activeSeconds));Spacer();Text(summary.rubles.map{Format.rub($0)} ?? summary.measuredRubles.map{Format.rub($0)+" учтено"} ?? "Нет оценки")}.font(.caption).monospacedDigit()
                                    if let dollars=store.exchangeRate?.dollars(for:summary.rubles ?? summary.measuredRubles) {
                                        Text("≈ "+Format.usd(dollars)+(summary.rubles == nil ? " учтено":"")+((store.exchangeRate?.isStale() == true || store.exchangeRateIssue != nil) ? " · сохранённый курс":""))
                                            .font(.caption).foregroundStyle(MeterTheme.secondary).monospacedDigit()
                                    }
                                }.padding(.vertical,6).textSelection(.disabled)
                                if summary.task.typeID==nil {
                                    Button {editing=summary.task} label:{Image(systemName:"tag.badge.plus")}
                                        .buttonStyle(.plain).foregroundStyle(MeterTheme.warning).help("Указать тип задачи")
                                        .accessibilityLabel("Указать тип: \(summary.task.title)").accessibilityIdentifier("task-needs-type-\(summary.id)")
                                }
                            }.tag(summary.id)
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
                    TaskBatchBar(count:tasksToActOn.count,total:visibleTasks.count,busy:store.isPerformingAction,selectAll:{
                        checkedTasks=tasksToActOn.count==visibleTasks.count ? []:Set(visibleTasks.map(\.id))
                    },clear:{checkedTasks=[]},action:{kind in
                        taskBatch=TaskBatchRequest(tasks:tasksToActOn,kind:kind)
                    })
                    HStack {
                        Text("Найдено: \(visibleTasks.count) из \(store.tasks.count)")
                        Spacer()
                        if !taskStatus.isEmpty || !taskKind.isEmpty {
                            Button("Сбросить фильтры") {taskStatus="";taskKind=""}.buttonStyle(.plain)
                        }
                    }.font(.caption2).foregroundStyle(MeterTheme.secondary)
                }
                Text(showUnassigned ? "Флажки выбирают запуски. Клик по карточке открывает переписку и сохраняет отметки.":"Флажки выбирают задачи. Открытие карточки сохраняет отметки.").font(.caption2).foregroundStyle(MeterTheme.secondary)
            }.padding(16).frame(minWidth:310,idealWidth:350,maxWidth:420,maxHeight:.infinity,alignment:.top)
            Group {
            if showUnassigned {
                if let run=store.runs.first(where:{$0.id==previewRun}) {
                    RunDetailView(run:run,assign:{assigning=RunAssignment(runs:[run])}).id(run.id)
                } else if !runsToAssign.isEmpty {
                    RunSelectionSummary(runs:runsToAssign,assign:{assigning=RunAssignment(runs:runsToAssign)})
                } else {
                    ContentUnavailableView("Выберите запуск",systemImage:"bubble.left.and.bubble.right",description:Text("Справа появятся ваши запросы, ответы Codex и контекст переписки. После просмотра запуск можно назначить задаче."))
                }
            } else if selectedTask == nil {
                TaskEmptyState()
            } else {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if let s=selectedTask {
                        HStack(alignment:.top){VStack(alignment:.leading,spacing:6){Text(s.task.title).font(.title2.weight(.semibold)).accessibilityIdentifier("task-detail-title");Text(s.task.typeLabel).foregroundStyle(MeterTheme.secondary)};Spacer();Button{editing=s.task}label:{Image(systemName:"pencil")}}
                        if store.tasks.count>1 {
                            Button("Объединить с задачей…",systemImage:"arrow.triangle.merge") {
                                taskBatch=TaskBatchRequest(tasks:[s],kind:.merge)
                            }.accessibilityIdentifier("task-merge-open")
                        }
                        if s.task.typeID==nil {
                            Button {editing=s.task} label:{Label("Указать тип задачи",systemImage:"tag")}
                                .foregroundStyle(MeterTheme.warning).accessibilityIdentifier("task-classify")
                        }
                        TaskOverview(summary:s)
                        TaskExecutionView(runs:s.runs)
                        HStack {
                            Button(s.task.status=="completed" ? "Открыть заново":"Завершить") {var task=s.task;task.status=task.status=="completed" ? "active":"completed";task.finished=task.status=="completed" ? Date():nil;save(task)}
                            if s.task.status != "cancelled" {Button("Отменить задачу"){var task=s.task;task.status="cancelled";task.finished=Date();save(task)}}
                        }
                        if !s.runs.isEmpty {
                            Text("Переписка задачи").font(.headline)
                            ForEach(s.runs.sorted{$0.started<$1.started}) {run in
                                Button {
                                    filter="";onlyUnassigned=false
                                    if run.isService {includeService=true}
                                    limit=max(100,(candidates.firstIndex{$0.id==run.id} ?? 0)+1)
                                    previewRun=run.id;showUnassigned=true
                                } label: {
                                    HStack{Text(run.title).lineLimit(2);Spacer();Image(systemName:"chevron.right")}
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                }.padding(22)
            }
            }
            }.frame(minWidth:420,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
        .onAppear {if !initialized {initialized=true;showUnassigned=store.tasks.isEmpty || previewRun != nil}}
        .onChange(of:filter){_,_ in searchMatches=[]}
        .onChange(of:runTypeFilter){_,_ in searchMatches=[];searchRevision += 1}
        .onChange(of:store.taskTypes.map(\.id)) {_,ids in
            if !taskKind.isEmpty && taskKind != "unclassified" && !ids.contains(taskKind) {taskKind=""}
            if !runTypeFilter.isEmpty && runTypeFilter != "unclassified" && !ids.contains(runTypeFilter) {runTypeFilter=""}
        }
        .onChange(of:shownRuns.map(\.id)){_,ids in
            checkedRuns.formIntersection(ids)
            if let previewRun,!ids.contains(previewRun) {self.previewRun=nil}
        }
        .onChange(of:visibleTasks.map(\.id)) {_,ids in
            checkedTasks.formIntersection(ids)
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
        .sheet(item:$taskBatch){request in TaskBatchEditor(request:request,onSaved:{target in
            checkedTasks.subtract(request.tasks.map(\.id))
            if let target {filter="";taskStatus="";taskKind="";selected=target}
        })}
        .sheet(item:$editing){task in TaskEditor(task:task)}
        .sheet(isPresented:$managingTypes){TaskTypesSheet()}
        .sheet(item:$assigning){selection in AssignEditor(runs:selection.runs,onAssigned:{checkedRuns.subtract(selection.runs.map(\.id))})}
    }
    func save(_ task:WorkTask){store.saveTask(task) {result in if case .failure(let error)=result {store.error=error.localizedDescription}}}
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
                            .font(.callout).foregroundStyle(MeterTheme.secondary)
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

struct TaskEditor:View {
    @EnvironmentObject var store:MeterStore
    @State private var issue:String?
    @Environment(\.dismiss) var dismiss
    @State var task:WorkTask
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Пользовательская задача").font(.title2)
            TextField("Конкретный результат: ревью API заказов",text:$task.title)
            TaskTypePicker(selection:Binding(get:{task.typeID ?? ""},set:{task.typeID=$0.isEmpty ? nil:$0}))
            if task.typeID==nil {
                Label("Нужно указать тип задачи",systemImage:"tag").foregroundStyle(MeterTheme.warning)
            }
            if let previous=task.legacyKind ?? (task.typeID==nil && !task.kind.isEmpty ? task.kind:nil) {
                Text("Прежнее значение: \(previous). Оно не считается подтверждённым типом.").font(.caption).foregroundStyle(MeterTheme.secondary)
            }
            if let issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.danger)}
            HStack {
                Button("Отмена"){dismiss()}
                Spacer()
                Button("Сохранить"){store.saveTask(task) {result in
                    switch result {case .success:dismiss();case .failure(let error):issue=error.localizedDescription}
                }}.buttonStyle(.borderedProminent).disabled(task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("task-editor-save")
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width:480).background(MeterTheme.background).actionProgress()
    }
}

struct RunAssignment:Identifiable {
    let id=UUID()
    let runs:[RunRecord]
}

struct AssignEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    var runs:[RunRecord]
    var onAssigned:()->Void = {}
    init(run:RunRecord) {self.runs=[run]}
    init(runs:[RunRecord],onAssigned:@escaping ()->Void = {}) {self.runs=runs;self.onAssigned=onAssigned}
    @State private var target=""
    @State private var title=""
    @State private var typeID=""
    @State private var creating=false
    @State private var issue:String?
    private var cleanTitle:String {title.trimmingCharacters(in:.whitespacesAndNewlines)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Добавить к задаче").font(.title2)
            Text(runs.count==1 ? "Выберите результат, к которому относится этот запрос.":"Выберите задачу для всех отмеченных запусков.")
                .font(.callout).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:6) {
                Text(runs.count==1 ? "Выбранный запрос":"Выбрано запусков: \(runs.count)").font(.caption.weight(.semibold)).accessibilityIdentifier("assignment-selection-count")
                ForEach(runs.prefix(3)) {run in
                    Text(run.title).font(.caption).foregroundStyle(MeterTheme.secondary).lineLimit(2)
                        .fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
                }
                if runs.count>3 {Text("И ещё \(runs.count-3)").font(.caption).foregroundStyle(MeterTheme.secondary)}
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(MeterTheme.surface,in:RoundedRectangle(cornerRadius:10))
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
                    Text("Например: Разработка Codex Meter или Ревью API заказов.").font(.caption).foregroundStyle(MeterTheme.secondary)
                }
                TaskTypePicker(selection:$typeID)
                if typeID.isEmpty {Text("Тип можно указать позже. Задача будет отмечена как требующая классификации.").font(.caption).foregroundStyle(MeterTheme.warning)}
            } else {
                TaskChooser(choices:TaskChoice.sorted(store.tasks),selection:$target,autofocus:true,confirm:addToTask)
                Text("Выбранные запуски дополнят историю, токены и время задачи. Если запуск уже относится к другой задаче, он будет перенесён.")
                    .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if let issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.danger)}
            HStack {
                Button("Отмена"){dismiss()}.accessibilityIdentifier("assignment-cancel")
                Spacer()
                Button(creating || store.tasks.isEmpty ? "Создать и добавить":"Добавить к задаче") {
                    addToTask()
                }.buttonStyle(.borderedProminent)
                .disabled(runs.isEmpty || (creating || store.tasks.isEmpty ? cleanTitle.isEmpty:!store.tasks.contains(where:{$0.id==target})))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("assignment-save")
            }
        }.textFieldStyle(.roundedBorder).padding(20).frame(width:580).background(MeterTheme.background).actionProgress()
        .onAppear{target=Set(runs.compactMap(\.taskID)).count==1 && runs.allSatisfy{$0.taskID != nil} ? runs.first?.taskID ?? "":"";creating=store.tasks.isEmpty}
    }
    private func addToTask() {
        guard let started=runs.map(\.started).min() else {return}
        var task:WorkTask
        if creating || store.tasks.isEmpty {
            guard !cleanTitle.isEmpty else { return }
            task=WorkTask(title:cleanTitle,kind:"",status:"paused",created:started)
            task.typeID=typeID.isEmpty ? nil:typeID
        } else {
            guard let existing=store.tasks.first(where:{$0.id==target})?.task else { return }
            task=existing
        }
        issue=nil
        store.assign(runs,to:task) {result in
            switch result {case .success:onAssigned();dismiss();case .failure(let error):issue=error.localizedDescription}
        }
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
                            BarMark(x:.value("Дата",date,unit:.day),y:.value("Токены",bucket.tokens)).foregroundStyle(MeterTheme.accent.gradient).cornerRadius(3)
                        }
                    }
                    .chartXAxis{AxisMarks(values:.stride(by:.day,count:days>30 ? 14:(days>7 ? 5:1))){_ in AxisGridLine();AxisValueLabel(format:.dateTime.day().month(.abbreviated))}}
                    .chartYAxis{AxisMarks(values:.automatic(desiredCount:4)){axis in AxisGridLine();AxisValueLabel{if let count=axis.as(Int64.self){Text(Format.tokens(count))}}}}
                    .frame(height:250)
                    Text("Источник: дневная статистика аккаунта Codex. Показана сумма полученных записей; полнота периода и часовой пояс серверных дней не гарантируются. Локальные данные ниже считаются отдельно.").font(.caption).foregroundStyle(MeterTheme.secondary)
                }
                Card {
                    Text("Сегодня на этом Mac").font(.headline)
                    let count=store.runs.flatMap(\.tokenEvents).filter{Calendar.current.isDateInToday($0.date)}.reduce(Int64(0)){$0+$1.tokens.total}
                    Metric(label:"По локальным событиям · ваш часовой пояс",value:Format.tokens(count)+" токенов")
                    Text("Включает размеченные и неразмеченные задачи. Не прибавляется к статистике аккаунта, чтобы избежать двойного счёта.").font(.caption).foregroundStyle(MeterTheme.secondary)
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
                Text("Раз в месяц внесите сумму, которую действительно заплатили в рублях. Дата окончания — начало следующего оплаченного периода.").foregroundStyle(MeterTheme.secondary)
                MoneyCard()
                ForEach(store.payments){payment in
                    Card {
                        HStack{Metric(label:"Оплачено",value:Format.rub(payment.amount));VStack(alignment:.leading){Text(payment.start.formatted(date:.abbreviated,time:.omitted)+" → "+payment.end.formatted(date:.abbreviated,time:.omitted));Text(payment.contains(Date()) ? "Текущий период":"История").font(.caption).foregroundStyle(MeterTheme.secondary)};Button("Изменить"){editing=payment}}
                    }
                }
                Card {
                    Text("Как считаются рубли").font(.headline)
                    Text("Цена задачи = платёж × длительность окна квоты / длительность оплаченного периода × использованная доля окна.").font(.callout)
                    Text("Вся внесённая сумма условно относится к Codex. Неиспользованная квота не увеличивает цену задач. Дополнительные лимиты моделей не суммируются с основной квотой. Смена тарифа или условий требует нового расчёта; приложение не считает процент квоты фиксированным количеством токенов.").font(.caption).foregroundStyle(MeterTheme.secondary)
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
            if let error {Text(error).font(.caption).foregroundStyle(MeterTheme.danger)}
            HStack{Button("Отмена"){dismiss()};Spacer();Button("Сохранить"){
                guard let value=Double(amount.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:",",with:".")) else{error="Введите сумму в рублях";return}
                payment.amount=value;payment.start=Calendar.current.startOfDay(for:payment.start);payment.end=Calendar.current.startOfDay(for:payment.end)
                self.error=nil
                store.savePayment(payment) {result in switch result {case .success:dismiss();case .failure(let error):self.error=error.localizedDescription}}
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("payment-save")}
        }.padding(24).frame(width:440).background(MeterTheme.background).actionProgress().onAppear{amount=payment.amount>0 ? String(payment.amount):""}
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
                        Text(issue).font(.caption).foregroundStyle(MeterTheme.warning)
                        Button("Открыть Системные настройки") {
                            if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences") {NSWorkspace.shared.open(url)}
                        }
                    }
                    TextField("Пороги расхода, %",text:$store.thresholds).textFieldStyle(.roundedBorder)
                    Text("50% — мягкое предупреждение. 80%, 90%, 95% — осталось 20%, 10%, 5%. Каждый порог срабатывает один раз за окно.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Toggle("Напоминать о большом остатке перед восстановлением",isOn:$store.expiryReminder)
                    HStack{Stepper("За \(store.expiryDays) дн.",value:$store.expiryDays,in:2...6);Spacer();Stepper("Остаток ≥ \(store.expiryRemaining)%",value:$store.expiryRemaining,in:5...95,step:5)}
                    Stepper("За сутки: остаток ≥ \(store.lastDayRemaining)%",value:$store.lastDayRemaining,in:5...95,step:5)
                    Text("Напоминание использует свежие данные и приходит один раз за недельное окно. После сна проверка выполняется при пробуждении.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    HStack {
                        Button("Сохранить пороги уведомлений") {
                            do {try store.saveAlertSettings();savedAlertSettings=alertSettingsKey}
                            catch {store.error=error.localizedDescription}
                        }.buttonStyle(.borderedProminent)
                        if savedAlertSettings==alertSettingsKey {Label("Сохранено",systemImage:"checkmark").font(.caption).foregroundStyle(MeterTheme.accent)}
                    }
                }
                SoftwareUpdateCard(updater:store.updates)
                ConnectionCard()
                Card {
                    Label(store.integrationInstalled ? "Учёт задач подключён":"Подключение учёта задач",systemImage:"link").font(.headline)
                    Text("Codex связывает запуски с задачей и проверяет прогноз. Статус меняете только вы в карточке задачи или через массовое действие.").font(.callout)
                    Text("Ожидание ответа, завершение работы агента и переключение задач не меняют статусы. Продолжение учёта не открывает завершённую задачу заново. Изменения подключения подхватываются в новых сессиях Codex.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Button("Открыть папку данных"){NSWorkspace.shared.open(Database.defaultDirectory)}
                }
                Text("Данные хранятся на этом Mac в SQLite. Сохраняются счётчики, короткие названия и связи задач; полная переписка не копируется. Формат журналов Codex может меняться — проверяйте свежесть данных после обновлений.").font(.caption).foregroundStyle(MeterTheme.secondary)
            }.padding(24)
        }
    }
}
