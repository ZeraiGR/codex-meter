import SwiftUI
import MeterCore

struct TaskStatusControl:View {
    @EnvironmentObject var store:MeterStore
    let task:WorkTask
    @State private var open=false
    @State private var issue:String?

    var body:some View {
        Button {issue=nil;open.toggle()} label:{TaskStatusBadge(status:task.status,interactive:true)}
            .buttonStyle(.plain).textSelection(.disabled)
            .help("Изменить статус задачи")
            .accessibilityIdentifier("task-detail-status")
            .disabled(store.isPerformingAction)
            .popover(isPresented:$open,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:8) {
                    Text("Статус задачи").font(.headline)
                    ForEach(["active","paused","ongoing","completed","cancelled","failed"],id:\.self) {status in
                        Button {change(to:status)} label:{
                            HStack {
                                TaskStatusBadge(status:status)
                                Spacer()
                                Image(systemName:"checkmark").opacity(task.status==status ? 1:0)
                            }.padding(4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("task-status-option-"+status)
                            .accessibilityValue(task.status==status ? "Текущий статус":"")
                    }
                    Text("Постоянная — открытая задача для регулярного пополнения контекста.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    if let issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.danger).accessibilityIdentifier("task-status-error")}
                }.padding(14).frame(width:260).textSelection(.disabled)
                    .background(MeterTheme.background).actionProgress()
                    // The popover owns its busy gate; do not retain the presenting
                    // window's disabled environment after a failed save.
                    .environment(\.isEnabled,true)
            }
    }

    private func change(to status:String) {
        guard status != task.status else {open=false;return}
        issue=nil
        let id=task.id
        store.performAction("Меняем статус задачи…",operation:{try $0.updateTaskStatuses([id],status:status)},completion:{result in
            switch result {
            case .success:open=false
            case .failure(let error):issue=error.localizedDescription
            }
        })
    }
}
