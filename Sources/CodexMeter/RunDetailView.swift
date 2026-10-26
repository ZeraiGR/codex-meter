import SwiftUI
import MeterCore

struct RunSelectionSummary:View {
    let runs:[RunRecord]
    let assign:()->Void
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Label("Выбрано запусков: \(runs.count)",systemImage:"checkmark.square.stack")
                    .font(.title2.weight(.semibold))
                Text("Назначьте выбранные запуски одной существующей или новой задаче. Клик по карточке откроет переписку и сохранит все отметки.")
                    .foregroundStyle(MeterTheme.secondary)
                Button(action:assign){Label("Назначить задачу",systemImage:"folder.badge.plus")}
                    .accessibilityIdentifier("run-summary-assign")
                Divider()
                ForEach(runs) {run in
                    VStack(alignment:.leading,spacing:4) {
                        Text(run.title).font(.callout.weight(.medium)).lineLimit(2)
                        Text(run.projectName+" · "+run.started.formatted(date:.abbreviated,time:.shortened))
                            .font(.caption).foregroundStyle(MeterTheme.secondary)
                    }
                }
            }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityIdentifier("run-selection-summary")
    }
}

struct RunListRow:View {
    let run:RunRecord
    let taskTitle:String?
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Image(systemName:run.isService ? "gearshape.2":run.category=="agent" ? "person.2":"bubble.left.and.bubble.right")
                Text(run.projectName).lineLimit(1)
                Spacer()
                Text(run.started.formatted(date:.omitted,time:.shortened)).monospacedDigit()
            }.font(.caption).foregroundStyle(.primary)
            Text(run.title).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(3).fixedSize(horizontal:false,vertical:true)
            if let preview=run.preview,!preview.isEmpty {Text(preview).font(.caption).foregroundStyle(.primary).lineLimit(2).fixedSize(horizontal:false,vertical:true)}
            HStack(spacing:5) {
                Text(Format.tokens(run.tokens.total)+" токенов")
                Text("·")
                Text(run.ended.map{Format.time($0.timeIntervalSince(run.started))} ?? "В работе")
                Spacer()
                if taskTitle != nil {Image(systemName:"checkmark.circle.fill").foregroundStyle(.primary)}
            }.font(.caption2).foregroundStyle(.primary)
            if let taskTitle {Text("Задача: "+taskTitle).font(.caption2).foregroundStyle(.primary).lineLimit(1)}
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,7).textSelection(.disabled)
    }
}

struct RunDetailView:View {
    @EnvironmentObject var store:MeterStore
    let run:RunRecord
    let assign:()->Void
    @State private var document:TranscriptDocument?
    @State private var loading=false
    @State private var issue:String?
    @State private var entireThread=false
    @State private var find=""
    @State private var showUpdates=true
    @State private var showContext=false
    @State private var editingType:WorkTask?
    private var taskTitle:String? {store.tasks.first{$0.id==run.taskID}?.task.title}
    private var visibleTurns:[TranscriptTurn] {
        (document?.turns ?? []).filter{entireThread || $0.id==run.id}.map { turn in
            var value=turn
            value.messages=turn.messages.filter { message in
                (showUpdates || message.role=="user" || message.phase != "commentary") &&
                (find.isEmpty || message.text.localizedCaseInsensitiveContains(find))
            }
            return value
        }.filter{!$0.messages.isEmpty}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:12) {
                RunHeading(title:run.title,subtitle:run.started.formatted(date:.abbreviated,time:.shortened)+" · "+run.categoryLabel,assigned:taskTitle != nil,assign:assign)
                HStack(spacing:18) {
                    Label(run.projectName,systemImage:"folder")
                    Text(Format.tokens(run.tokens.total)+" токенов")
                    Text((run.model.isEmpty ? "Модель не указана":run.model)+(run.effort.isEmpty ? "":" · "+run.effort))
                }.font(.caption).foregroundStyle(MeterTheme.secondary)
                if let taskTitle {Label(taskTitle,systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(MeterTheme.accent)}
                else {Text("Пока без задачи. Прочитайте переписку и выберите, к какому результату относится этот запуск.").font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)}
                if let task=store.tasks.first(where:{$0.id==run.taskID})?.task,task.typeID != nil {
                    Label(task.typeLabel,systemImage:"tag").font(.caption)
                } else {
                    Button {
                        if let task=store.tasks.first(where:{$0.id==run.taskID})?.task {editingType=task} else {assign()}
                    } label:{Label("Указать тип задачи",systemImage:"tag")}
                        .controlSize(.small).foregroundStyle(MeterTheme.warning).accessibilityIdentifier("run-classify")
                }
                HStack {
                    Picker("Показать",selection:$entireThread){Text("Этот запуск").tag(false);Text("Вся переписка").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(maxWidth:290)
                    Spacer()
                    Button {showContext=true} label:{Image(systemName:"info.circle")}
                        .help("Контекст запуска: модель, рассуждение, harness и MCP").accessibilityLabel("Контекст запуска").accessibilityIdentifier("run-execution-context")
                    if let path=run.sourcePath {Button{NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])}label:{Image(systemName:"folder")}.help("Показать журнал в Finder")}
                }
                HStack {
                    TextField("Найти в сообщениях",text:$find).textFieldStyle(.roundedBorder)
                    Toggle("Промежуточные ответы",isOn:$showUpdates).toggleStyle(.checkbox).font(.caption)
                }
            }.padding(20)
            Divider()
            if loading {ProgressView("Открываем переписку…").frame(maxWidth:.infinity,maxHeight:.infinity)}
            else if run.isService {
                ContentUnavailableView("Автоматическая проверка",systemImage:"gearshape.2",description:Text("Это служебная проверка действия Codex, а не запрос пользователя. Её счётчики сохранены. Внутренняя история проверки не показывается как переписка."))
            } else if let issue {
                ContentUnavailableView("Журнал недоступен",systemImage:"doc.questionmark",description:Text(issue))
            } else if visibleTurns.isEmpty {
                ContentUnavailableView(find.isEmpty ? "Нет сохранённых сообщений":"Совпадений нет",systemImage:"text.bubble",description:Text(find.isEmpty ? "В этом фрагменте нет запросов и ответов. Откройте всю переписку для контекста. Инструменты и внутренние рассуждения здесь не отображаются.":"Измените запрос или включите промежуточные ответы."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:16) {
                            ForEach(visibleTurns) {turn in
                                if entireThread {
                                    HStack{Text(turn.date.formatted(date:.abbreviated,time:.shortened));if turn.id==run.id {Text("Выбранный запуск").foregroundStyle(MeterTheme.accent)};Spacer()}.font(.caption.weight(.medium)).foregroundStyle(MeterTheme.secondary).padding(.top,8).id(turn.id)
                                }
                                ForEach(turn.messages) {message in MessageCard(message:message)}
                            }
                        }.padding(20)
                    }
                    .onChange(of:entireThread) {_,value in if value {DispatchQueue.main.async{proxy.scrollTo(run.id,anchor:.top)}}}
                }
            }
            Divider()
            HStack {
                Text("Сообщения читаются из локального журнала Codex").font(.caption2).foregroundStyle(MeterTheme.secondary)
                Spacer()
                Button("Копировать переписку") {
                    Clipboard.copy(visibleTurns.flatMap(\.messages).map{($0.role=="user" ? "Вы":"Codex")+"\n"+$0.text}.joined(separator:"\n\n"))
                }.controlSize(.small).disabled(visibleTurns.isEmpty)
            }.padding(12)
        }.textSelection(.enabled)
        .sheet(item:$editingType){TaskEditor(task:$0)}
        .sheet(isPresented:$showContext) {
            VStack(alignment:.leading,spacing:16) {
                HStack {Text("Контекст запуска").font(.title2);Spacer();Button("Готово"){showContext=false}.keyboardShortcut(.cancelAction)}
                ScrollView {ExecutionContextView(run:run).frame(maxWidth:.infinity,alignment:.leading)}
            }.padding(24).frame(width:580,height:560)
        }
        .task(id:"\(run.id):\(run.sourcePath ?? ""):\(run.messageCount ?? 0)") {
            document=nil;issue=nil;loading=true
            guard !run.isService else {loading=false;return}
            guard let path=run.sourcePath else {issue="У записи нет пути к журналу. Дождитесь повторного импорта локальной истории.";loading=false;return}
            do {
                let value=try await TranscriptRepository.shared.read(path:path)
                try Task.checkCancellation();document=value;loading=false
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else{return}
                issue="Файл мог быть перемещён или удалён. Обновите историю. Счётчики и назначенная задача сохранены.";loading=false
            }
        }
    }
}

private struct MessageCard:View {
    let message:TranscriptMessage
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label(message.role=="user" ? "Вы":"Codex",systemImage:message.role=="user" ? "person.crop.circle":"sparkle").font(.callout.weight(.semibold))
                if message.phase=="commentary" {Text("По ходу работы").font(.caption).foregroundStyle(MeterTheme.secondary)}
                Spacer()
                Text(message.date.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(MeterTheme.secondary)
                Button{Clipboard.copy(message.text)}label:{Image(systemName:"doc.on.doc")}.buttonStyle(.plain).help("Скопировать сообщение")
            }
            MessageText(text:message.text)
        }.padding(15).background(message.role=="user" ? MeterTheme.accent.opacity(0.08):Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
    }
}

private struct MessageText:View {
    let text:String
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            ForEach(Array(text.components(separatedBy:"```").enumerated()),id:\.offset) {index,part in
                if index%2==0 {
                    Text((try? AttributedString(markdown:part,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(part))
                        .font(.system(size:13)).lineSpacing(4).frame(maxWidth:.infinity,alignment:.leading)
                } else {
                    let lines=part.components(separatedBy:"\n")
                    ScrollView(.horizontal) {
                        Text(lines.dropFirst().joined(separator:"\n")).font(.system(size:12,design:.monospaced)).padding(10)
                    }.background(.quaternary,in:RoundedRectangle(cornerRadius:6))
                }
            }
        }.textSelection(.enabled)
    }
}

/// Selectable Text must have room for its full content: macOS selection exposes
/// truncated lines without increasing the surrounding SwiftUI layout height.
struct RunHeading:View {
    let title:String
    let subtitle:String
    let assigned:Bool
    let assign:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.title3.weight(.semibold))
                .fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity,alignment:.leading)
                .accessibilityIdentifier("run-heading-title")
            HStack(alignment:.center,spacing:8) {
                Text(subtitle).font(.caption).foregroundStyle(MeterTheme.secondary)
                    .fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("run-heading-subtitle")
                Spacer(minLength:0)
                Button(assigned ? "Изменить задачу":"Назначить задаче",action:assign)
                    .buttonStyle(.borderedProminent).controlSize(.small).fixedSize()
            }
        }.textSelection(.enabled)
    }
}
