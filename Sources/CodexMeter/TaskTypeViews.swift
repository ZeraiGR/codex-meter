import SwiftUI
import MeterCore

struct TaskTypePicker:View {
    @EnvironmentObject var store:MeterStore
    @Binding var selection:String
    @State private var managing=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Picker("Тип задачи",selection:$selection) {
                Text("Тип не указан").tag("")
                ForEach(store.taskTypes.filter{!$0.archived || $0.id==selection}) {type in
                    Text(type.name+(type.archived ? " · архив":"")).tag(type.id)
                }
            }.accessibilityIdentifier("task-type-picker")
            Button("Настроить типы…"){managing=true}.font(.caption).accessibilityIdentifier("task-types-manage")
        }.sheet(isPresented:$managing){VStack {TaskTypesManager();Button("Готово"){managing=false}.disabled(store.isPerformingAction)}.padding(24).frame(width:520)}
    }
}

struct TaskTypesManager:View {
    @EnvironmentObject var store:MeterStore
    @State private var editing:TaskType?
    @State private var issue:String?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Типы задач").font(.headline);Spacer();Button("Добавить тип",systemImage:"plus"){editing=TaskType(name:"")}.accessibilityIdentifier("task-type-add")}
            Text("Общий справочник для задач и фильтров. Скилл не определяет тип автоматически. Архивные типы сохраняются в истории, но не предлагаются для новых назначений.")
                .font(.caption).foregroundStyle(MeterTheme.secondary)
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    ForEach(store.taskTypes) {type in
                        HStack {
                            Text(type.name).frame(maxWidth:.infinity,alignment:.leading)
                            if type.archived {Text("Архив").font(.caption).foregroundStyle(MeterTheme.secondary)}
                            Button {editing=type} label:{Image(systemName:"pencil")}.help("Переименовать тип").accessibilityLabel("Переименовать: \(type.name)")
                            Button(type.archived ? "Вернуть":"В архив") {
                                var updated=type;updated.archived.toggle();let value=updated
                                store.performAction("Сохраняем тип…",operation:{try $0.saveTaskType(value)},completion:{if case .failure(let error)=$0 {issue=error.localizedDescription}})
                            }.accessibilityIdentifier("task-type-archive-\(type.id)")
                        }
                    }
                }
            }.frame(maxHeight:260)
            if let issue {Text(issue).font(.caption).foregroundStyle(.red)}
        }.disabled(store.isPerformingAction)
            .sheet(item:$editing){TaskTypeEditor(type:$0)}
    }
}

struct TaskTypeEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    @State var type:TaskType
    @State private var issue:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Тип задачи").font(.title2)
            TextField("Название типа",text:$type.name).textFieldStyle(.roundedBorder).accessibilityIdentifier("task-type-name")
            Text("Переименование отобразится во всех связанных задачах. Их история и расход сохранятся.").font(.caption).foregroundStyle(MeterTheme.secondary)
            if let issue {Text(issue).foregroundStyle(.red).accessibilityIdentifier("task-type-error")}
            HStack {
                Button("Отмена"){dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") {
                    let type=type
                    store.performAction("Сохраняем тип…",operation:{try $0.saveTaskType(type)},completion:{result in
                        switch result {case .success:dismiss();case .failure(let error):issue=error.localizedDescription}
                    })
                }.keyboardShortcut(.defaultAction).disabled(type.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("task-type-save")
            }
        }.padding(24).frame(width:420).disabled(store.isPerformingAction).interactiveDismissDisabled(store.isPerformingAction)
    }
}
