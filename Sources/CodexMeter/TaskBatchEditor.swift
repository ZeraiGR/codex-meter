import SwiftUI
import MeterCore

struct TaskCheckButton:View {
    let title:String
    let id:String
    let checked:Bool
    let toggle:()->Void
    var body:some View {
        Button(action:toggle) {
            ZStack {
                RoundedRectangle(cornerRadius:4).fill(checked ? Color(red:0,green:0.32,blue:0.72):MeterTheme.background)
                RoundedRectangle(cornerRadius:4).strokeBorder(checked ? Color.white:MeterTheme.secondary,lineWidth:1.5)
                if checked {Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(.white)}
            }.frame(width:20,height:20).frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Отметить: \(title)")
            .accessibilityValue(checked ? "Отмечена":"Не отмечена").accessibilityIdentifier("task-check-\(id)")
            .help("Изменить отметку только этой задачи")
    }
}

enum TaskBatchKind:String {case type="Указать тип",status="Изменить статус",merge="Объединить задачи"}
struct TaskBatchRequest:Identifiable {
    let id=UUID()
    let tasks:[TaskSummary]
    let kind:TaskBatchKind
}

struct TaskBatchBar:View {
    let count:Int
    let total:Int
    let busy:Bool
    let selectAll:()->Void
    let clear:()->Void
    let action:(TaskBatchKind)->Void
    var body:some View {
        HStack(spacing:8) {
            Button(action:selectAll){Image(systemName:count==0 ? "square":count==total ? "checkmark.square.fill":"minus.square.fill")}
                .accessibilityLabel("Выбрать показанные задачи").accessibilityIdentifier("task-select-visible")
                .help("Выбрать или снять выбор показанных задач (\(total))").disabled(total==0)
            // Recreate the static AX text so VoiceOver receives the updated count.
            Text("Выбрано: \(count)").monospacedDigit().accessibilityIdentifier("task-selection-count").id(count)
            Spacer(minLength:0)
            if count>0 {
                Menu {
                    Button("Указать тип",systemImage:"tag"){action(.type)}
                    Button("Изменить статус",systemImage:"checkmark.circle"){action(.status)}
                    Button("Объединить задачи",systemImage:"arrow.triangle.merge"){action(.merge)}
                } label:{Label("Действия",systemImage:"ellipsis.circle")}
                    .accessibilityIdentifier("task-batch-actions").disabled(busy)
                Button(action:clear){Image(systemName:"xmark")}.help("Снять все отметки")
                    .accessibilityLabel("Снять отметки задач").accessibilityIdentifier("task-clear-selection")
            }
        }.font(.caption).controlSize(.small).frame(height:28)
    }
}

struct TaskSelectionSummary:View {
    let tasks:[TaskSummary]
    let busy:Bool
    let action:(TaskBatchKind)->Void
    let remove:(String)->Void
    let clear:()->Void
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Label("Выбрано задач: \(tasks.count)",systemImage:"checkmark.square.stack")
                    .font(.title2.weight(.semibold))
                Text("Действие применяется ко всем отмеченным задачам. Снимите лишние отметки здесь или флажками слева.")
                    .foregroundStyle(MeterTheme.secondary)
                VStack(alignment:.leading,spacing:10) {
                    Button("Указать тип",systemImage:"tag"){action(.type)}.accessibilityIdentifier("task-summary-type")
                    Button("Изменить статус",systemImage:"checkmark.circle"){action(.status)}.accessibilityIdentifier("task-summary-status")
                    Button("Объединить задачи",systemImage:"arrow.triangle.merge"){action(.merge)}.accessibilityIdentifier("task-summary-merge")
                }.disabled(busy)
                Button("Снять все отметки",action:clear).accessibilityIdentifier("task-summary-clear")
                Divider()
                ForEach(tasks) {summary in
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Text(summary.task.title).font(.callout.weight(.medium)).lineLimit(2)
                            HStack {Text(summary.task.typeLabel);TaskStatusBadge(status:summary.task.status)}
                                .font(.caption).foregroundStyle(MeterTheme.secondary)
                        }
                        Spacer()
                        Button {remove(summary.id)} label:{Image(systemName:"xmark.circle").frame(width:44,height:44).contentShape(Rectangle())}
                            .buttonStyle(.plain)
                            .help("Снять отметку: \(summary.task.title)").accessibilityLabel("Снять отметку: \(summary.task.title)")
                            .accessibilityIdentifier("task-summary-remove-\(summary.id)")
                    }
                }
            }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityIdentifier("task-selection-summary")
    }
}

struct TaskBatchEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    let request:TaskBatchRequest
    let onSaved:(String?)->Void
    @State private var status="completed"
    @State private var typeID=""
    @State private var target=""
    @State private var issue:String?
    private var ids:[String] {request.tasks.map(\.id)}
    private var singleMerge:Bool {request.kind == .merge && ids.count==1}
    private var destination:TaskSummary? {store.tasks.first{$0.id==target}}
    private var valid:Bool {
        switch request.kind {
        case .type:return !typeID.isEmpty
        case .status:return true
        case .merge:return destination != nil && ids.contains{$0 != target}
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(singleMerge ? "Объединить задачу":request.kind.rawValue).font(.title2.weight(.semibold))
            if singleMerge,let source=request.tasks.first {
                Text("Текущая задача: \(source.task.title)").font(.callout).lineLimit(2).help(source.task.title)
                    .accessibilityIdentifier("task-merge-source")
            } else {
                Text("Выбрано задач: \(ids.count)").font(.headline)
                DisclosureGroup("Выбранные задачи") {
                    ScrollView {VStack(alignment:.leading,spacing:6){ForEach(request.tasks){Text($0.task.title)}}}.frame(maxHeight:100)
                }.font(.caption)
            }
            switch request.kind {
            case .type:
                TaskTypePicker(selection:$typeID)
                Text("Тип будет назначен всем выбранным задачам и их запускам.").font(.caption)
            case .status:
                Picker("Новый статус",selection:$status) {
                    Text("В работе").tag("active")
                    Text("Ожидает").tag("paused")
                    Text("Постоянная").tag("ongoing")
                    Text("Завершена").tag("completed")
                    Text("Отменена").tag("cancelled")
                    Text("Не удалась").tag("failed")
                }.accessibilityIdentifier("task-batch-status")
                Text("Изменится статус всех выбранных задач. Запуски и расход сохранятся.").font(.callout).foregroundStyle(MeterTheme.secondary)
            case .merge:
                Text("В какую задачу перенести запуски?").font(.headline)
                TaskChooser(choices:TaskChoice.sorted(store.tasks,excluding:singleMerge ? ids.first:nil),selection:$target,autofocus:true,showsFilters:!singleMerge,confirm:{if valid && !store.isPerformingAction {save()}})
                if let destination {
                    Text(singleMerge ? "Запуски и расход текущей задачи перейдут в «\(destination.task.title)». Её название, тип и статус сохранятся, текущая карточка будет удалена. Отменить объединение автоматически нельзя.":"В «\(destination.task.title)» будут перенесены все запуски и привязки. Остальные выбранные карточки (\(ids.filter{$0 != target}.count)) будут удалены. Название и статус итоговой задачи сохранятся. Отменить объединение автоматически нельзя.")
                        .font(.callout).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }
            if let issue {Text(issue).foregroundStyle(.red).font(.callout).accessibilityIdentifier("task-batch-error")}
            HStack {
                Button("Отмена"){dismiss()}.keyboardShortcut(.cancelAction).disabled(store.isPerformingAction)
                    .accessibilityIdentifier("task-batch-cancel")
                Spacer()
                if store.isPerformingAction {ProgressView().controlSize(.small)}
                Button(request.kind == .merge ? "Объединить":"Применить",action:save)
                    .keyboardShortcut(.defaultAction).disabled(!valid || store.isPerformingAction).accessibilityIdentifier("task-batch-save")
            }
        }.padding(24).frame(width:520).interactiveDismissDisabled(store.isPerformingAction)
            .disabled(store.isPerformingAction)
    }
    private func save() {
        let ids=ids,status=status,target=target,kind=request.kind,typeID=typeID
        issue=nil
        store.performAction("Сохраняем выбранные задачи…",operation:{db in
            switch kind {
            case .type:try db.assignTaskType(ids,typeID:typeID)
            case .status:try db.updateTaskStatuses(ids,status:status)
            case .merge:try db.mergeTasks(sources:ids,target:target)
            }
        },completion:{result in
            switch result {
            case .success:onSaved(kind == .merge ? target:nil);dismiss()
            case .failure(let error):issue=error.localizedDescription
            }
        })
    }
}
