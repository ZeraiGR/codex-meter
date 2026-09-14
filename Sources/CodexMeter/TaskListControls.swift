import SwiftUI
import MeterCore

extension TaskSort {
    var label:String {
        switch self {case .recent:return "Недавняя активность";case .tokens:return "Токены";case .time:return "Время выполнения";case .cost:return "Учтённая стоимость";case .quota:return "Недельная квота";case .title:return "Название"}
    }
}

struct TaskListControls:View {
    @Binding var sort:TaskSort
    @Binding var ascending:Bool
    @Binding var status:String
    @Binding var kind:String
    @State private var filtersOpen=false
    private var filterCount:Int {(status.isEmpty ? 0:1)+(kind.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0:1)}
    var body:some View {
        HStack(spacing:6) {
            Picker("Сортировка задач",selection:$sort) {
                ForEach(TaskSort.allCases,id:\.self) {Text($0.label).tag($0)}
            }.labelsHidden().accessibilityIdentifier("task-list-sort")
                .help("Стоимость и недельная квота сортируются по учтённой части. Неизвестные значения всегда в конце.")
            Button {ascending.toggle()} label:{Image(systemName:ascending ? "arrow.up":"arrow.down")}
                .help(ascending ? "По возрастанию. Нажмите, чтобы изменить":"По убыванию. Нажмите, чтобы изменить")
                .accessibilityLabel(ascending ? "По возрастанию":"По убыванию").accessibilityIdentifier("task-list-direction")
            Button {filtersOpen.toggle()} label:{Label(filterCount==0 ? "Фильтры":"Фильтры · \(filterCount)",systemImage:"line.3.horizontal.decrease")}
                .labelStyle(.titleAndIcon).fixedSize().accessibilityIdentifier("task-list-filters")
                .popover(isPresented:$filtersOpen) {
                    VStack(alignment:.leading,spacing:14) {
                        Text("Фильтры задач").font(.headline)
                        Picker("Статус",selection:$status) {
                            Text("Все статусы").tag("")
                            Text("В работе").tag("active")
                            Text("Ожидает").tag("paused")
                            Text("Завершена").tag("completed")
                            Text("Отменена").tag("cancelled")
                        }.accessibilityIdentifier("task-list-status")
                        VStack(alignment:.leading,spacing:5) {
                            Text("Тип содержит").font(.caption)
                            TextField("Например: code-review",text:$kind).textFieldStyle(.roundedBorder).accessibilityIdentifier("task-list-kind")
                        }
                        HStack {
                            Button("Сбросить") {status="";kind=""}.disabled(filterCount==0)
                            Spacer()
                            Button("Готово") {filtersOpen=false}.keyboardShortcut(.defaultAction).accessibilityIdentifier("task-list-filters-done")
                        }
                    }.padding(18).frame(width:280)
                }
        }.font(.caption)
        .onChange(of:sort) {_,value in ascending = value == .title}
    }
}
