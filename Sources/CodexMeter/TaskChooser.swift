import SwiftUI
import MeterCore

/// Lightweight rows: searching never reads transcripts or recalculates attribution.
struct TaskChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let kind: String
    let status: String
    let activity: Date
    let runCount: Int
    let searchText: String
    var closed: Bool { status == "completed" || status == "cancelled" }
    var statusLabel: String {
        switch status {
        case "active": return "В работе"
        case "completed": return "Завершена"
        case "cancelled": return "Отменена"
        default: return "Ожидает"
        }
    }
    init(_ summary: TaskSummary) {
        let task=summary.task
        id=task.id;title=task.title;kind=task.kind;status=task.status;runCount=summary.runs.count
        activity=max(task.created,task.finished ?? task.created,summary.runs.map { $0.ended ?? $0.started }.max() ?? task.created)
        searchText=Self.normalize(task.title+" "+task.kind)
    }
    static func normalize(_ value:String)->String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"ru_RU"))
    }
    static func sorted(_ summaries:[TaskSummary],excluding:String? = nil)->[TaskChoice] {
        summaries.filter { $0.id != excluding }.map(Self.init).sorted {
            if $0.activity != $1.activity { return $0.activity > $1.activity }
            return $0.id < $1.id
        }
    }
    static func matching(_ choices:[Self],query:String,scope:Int)->[Self] {
        let words=normalize(query).split(whereSeparator: { $0.isWhitespace })
        return choices.filter { row in
            (scope == 0 || (scope == 1 ? !row.closed : row.closed)) && words.allSatisfy { row.searchText.contains($0) }
        }
    }
}

struct TaskChooser: View {
    let choices: [TaskChoice]
    @Binding var selection: String
    @State private var query=""
    @State private var scope=0
    var autofocus=false
    var confirm:()->Void = {}
    private var matches:[TaskChoice] { TaskChoice.matching(choices,query:query,scope:scope) }
    private var selected:TaskChoice? { choices.first { $0.id == selection } }
    private var listSelection:Binding<String?> {
        Binding(get:{ selection.isEmpty ? nil : selection },set:{ selection=$0 ?? "" })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            TaskSearchField(text:$query,autofocus:autofocus,move:move,confirm:confirm)
                .frame(height:28)
            Picker("Статус задач",selection:$scope) {
                Text("Все").tag(0)
                Text("Открытые").tag(1)
                Text("Завершённые").tag(2)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("task-choice-scope")
            HStack {
                Text("Найдено: \(matches.count) из \(choices.count)")
                    .accessibilityIdentifier("task-choice-count")
                Spacer()
                Text("Недавние сверху")
            }.font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                List(selection:listSelection) {
                    ForEach(matches) { row in
                        VStack(alignment:.leading,spacing:4) {
                            Text(row.title).font(.callout.weight(.medium)).lineLimit(2)
                                .frame(maxWidth:.infinity,alignment:.leading)
                            HStack(spacing:8) {
                                Text(row.kind).lineLimit(1)
                                Spacer(minLength:4)
                                Text(row.statusLabel)
                                Text(row.activity,format:.dateTime.day().month(.abbreviated).year())
                            }.font(.caption).foregroundStyle(.secondary)
                        }.frame(height:56,alignment:.center).padding(.vertical,3)
                            .contentShape(Rectangle()).tag(row.id).id(row.id)
                            .help("\(row.title)\n\(row.kind) · \(row.statusLabel)\nЗапросов: \(row.runCount) · ID: \(row.id)")
                            .accessibilityIdentifier("task-choice-\(row.id)")
                    }
                }.listStyle(.bordered).frame(height:210)
                    .accessibilityIdentifier("task-choice-list")
                    .overlay {
                        if matches.isEmpty {
                            VStack(spacing:6) {
                                Text("Задачи не найдены").font(.headline)
                                Text("Измените поиск или выберите «Все».").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,maxHeight:.infinity).allowsHitTesting(false)
                        }
                    }
                    .onChange(of:selection) { _,id in
                        if !id.isEmpty { DispatchQueue.main.async { if selection==id { proxy.scrollTo(id) } } }
                    }
                    .onAppear { DispatchQueue.main.async { if !selection.isEmpty { proxy.scrollTo(selection) } } }
            }
            Group {
                if let selected {
                    Text("Выбрана: \(selected.title)").font(.caption.weight(.medium)).lineLimit(2)
                        .help("\(selected.title)\n\(selected.kind) · ID: \(selected.id)")
                } else {
                    Text("Выберите задачу · ↑ ↓ — перемещение по списку").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height:30,alignment:.topLeading).accessibilityIdentifier("task-choice-selected")
        }
        // A changed query must never leave an invisible assignment selected.
        .onChange(of:query) { _,_ in selection="" }
        .onChange(of:scope) { _,_ in selection="" }
        .onChange(of:choices) { _,_ in
            if !selection.isEmpty && !matches.contains(where:{$0.id==selection}) { selection="" }
        }
    }
    private func move(_ direction:Int) {
        let rows=matches
        guard !rows.isEmpty else { return }
        let current=rows.firstIndex { $0.id == selection }
        let index=current.map { max(0,min(rows.count-1,$0+direction)) } ?? (direction>0 ? 0:rows.count-1)
        selection=rows[index].id
    }
}

/// NSSearchField keeps native editing/cancel behavior and handles arrows while typing.
private struct TaskSearchField:NSViewRepresentable {
    @Binding var text:String
    var autofocus:Bool
    var move:(Int)->Void
    var confirm:()->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeNSView(context:Context)->NSSearchField {
        let field=NSSearchField()
        field.placeholderString="Поиск по названию или типу"
        field.setAccessibilityIdentifier("task-choice-search")
        field.setAccessibilityLabel("Поиск задач по названию или типу")
        field.delegate=context.coordinator
        field.sendsSearchStringImmediately=true
        field.maximumRecents=0
        if autofocus { DispatchQueue.main.async { field.window?.makeFirstResponder(field) } }
        return field
    }
    func updateNSView(_ field:NSSearchField,context:Context) {
        context.coordinator.parent=self
        if field.stringValue != text { field.stringValue=text }
    }
    final class Coordinator:NSObject,NSSearchFieldDelegate {
        var parent:TaskSearchField
        init(_ parent:TaskSearchField) { self.parent=parent }
        func controlTextDidChange(_ notification:Notification) {
            guard let field=notification.object as? NSSearchField else{return}
            parent.text=field.stringValue
        }
        func control(_ control:NSControl,textView:NSTextView,doCommandBy commandSelector:Selector)->Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) { parent.move(1);return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { parent.move(-1);return true }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { parent.confirm();return true }
            return false
        }
    }
}
