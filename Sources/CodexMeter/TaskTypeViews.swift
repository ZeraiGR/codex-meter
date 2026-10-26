import SwiftUI
import MeterCore

struct TaskTypeFilter:View {
    @EnvironmentObject var store:MeterStore
    @Binding var selection:String
    var body:some View {
        Picker("Тип задачи",selection:$selection) {
            Text("Все типы").tag("")
            Text("Тип не указан").tag("unclassified")
            ForEach(store.taskTypes){type in Text(type.name+(type.archived ? " · архив":"")).tag(type.id)}
        }.onChange(of:store.taskTypes.map(\.id)) {_,ids in
            if !selection.isEmpty && selection != "unclassified" && !ids.contains(selection) {selection=""}
        }
    }
}

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
        }.sheet(isPresented:$managing){TaskTypesSheet()}
            .onChange(of:store.taskTypes.map(\.id)) {_,ids in if !selection.isEmpty && !ids.contains(selection) {selection=""}}
    }
}

struct TaskTypesManager:View {
    @EnvironmentObject var store:MeterStore
    @State private var editing:TaskType?
    @State private var deleting:TaskType?
    @State private var issue:String?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Типы задач").font(.title2.weight(.semibold));Spacer();Button("Добавить тип",systemImage:"plus"){editing=TaskType(name:"")}.accessibilityIdentifier("task-type-add")}
            Text("Ваш общий список для задач и фильтров. Архив скрывает тип при новых назначениях; удаление снимает тип с задач, сохраняя их историю.")
                .font(.caption).foregroundStyle(MeterTheme.secondary)
            if store.taskTypes.isEmpty {
                ContentUnavailableView("Добавьте первый тип",systemImage:"tag",description:Text("Назовите типы так, как удобно вам. Готового списка нет."))
                    .frame(height:200).accessibilityIdentifier("task-types-empty")
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        ForEach(store.taskTypes) {type in
                            HStack {
                                Text(type.name).frame(maxWidth:.infinity,alignment:.leading)
                                if type.archived {Text("Архив").font(.caption).foregroundStyle(MeterTheme.secondary)}
                                Button {editing=type} label:{Image(systemName:"pencil")}.help("Переименовать тип").accessibilityLabel("Переименовать: \(type.name)")
                                Button(type.archived ? "Вернуть":"В архив") {
                                    issue=nil
                                    var updated=type;updated.archived.toggle();let value=updated
                                    store.performAction("Сохраняем тип…",operation:{try $0.saveTaskType(value)},completion:{if case .failure(let error)=$0 {issue=error.localizedDescription}})
                                }.accessibilityIdentifier("task-type-archive-\(type.id)")
                                Button(role:.destructive) {deleting=type} label:{Image(systemName:"trash")}
                                    .help("Удалить тип").accessibilityLabel("Удалить: \(type.name)").accessibilityIdentifier("task-type-delete-\(type.id)")
                            }
                        }
                    }
                }.frame(height:260)
            }
            if let issue {Text(issue).font(.caption).foregroundStyle(.red)}
        }.actionProgress()
            .sheet(item:$editing){TaskTypeEditor(type:$0)}
            .sheet(item:$deleting){TaskTypeDeleteEditor(type:$0)}
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
        }.padding(24).frame(width:420).actionProgress()
    }
}

struct TaskTypesSheet:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    var body:some View {
        VStack(alignment:.trailing,spacing:16) {
            TaskTypesManager()
            Button("Готово"){dismiss()}.keyboardShortcut(.cancelAction).disabled(store.isPerformingAction)
                .accessibilityIdentifier("task-types-done")
        }.padding(24).frame(width:560).interactiveDismissDisabled(store.isPerformingAction)
    }
}

struct TaskTypeDeleteEditor:View {
    @EnvironmentObject var store:MeterStore
    @Environment(\.dismiss) var dismiss
    let type:TaskType
    @State private var issue:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Удалить тип «\(type.name)»?").font(.title2)
            Text("Задач с этим типом: \(store.tasks.filter{$0.task.typeID==type.id}.count). Они и их запуски останутся, но будут отмечены как «Тип не указан». Расход и история сохранятся.")
                .fixedSize(horizontal:false,vertical:true)
            if let issue {Text(issue).foregroundStyle(.red).accessibilityIdentifier("task-type-delete-error")}
            HStack {
                Button("Отмена"){dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Удалить тип",role:.destructive) {
                    let id=type.id
                    store.performAction("Удаляем тип…",operation:{try $0.deleteTaskType(id)},completion:{result in
                        switch result {case .success:dismiss();case .failure(let error):issue=error.localizedDescription}
                    })
                }.accessibilityIdentifier("task-type-delete-confirm")
            }
        }.padding(24).frame(width:460).actionProgress()
    }
}
