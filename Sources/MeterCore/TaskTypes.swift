import Foundation

public struct TaskType:Codable,Identifiable,Equatable {
    public var id:String
    public var name:String
    public var archived:Bool
    public init(id:String=UUID().uuidString,name:String,archived:Bool=false){self.id=id;self.name=name;self.archived=archived}
}

extension WorkTask {
    public var typeLabel:String {typeID == nil ? "Тип не указан":kind}
}

extension Database {
    public func taskTypes() throws -> [TaskType] {
        try query("SELECT data FROM task_types").map{try Codec.decode(TaskType.self,$0["data"]!)}.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    public func saveTaskType(_ value:TaskType) throws {
        var value=value;value.name=value.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.name.isEmpty else {throw MeterError("Введите название типа")}
        try transaction {
            let key=value.name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"ru_RU"))
            guard try !taskTypes().contains(where:{$0.id != value.id && $0.name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"ru_RU"))==key}) else {throw MeterError("Тип с таким названием уже существует, в том числе среди архивных")}
            try exec("INSERT INTO task_types VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",[value.id,try Codec.encode(value)])
        }
    }
    public func assignTaskType(_ ids:[String],typeID:String?) throws {
        guard !ids.isEmpty else {throw MeterError("Выберите задачи")}
        try transaction {
            if let typeID {guard try taskTypes().contains(where:{$0.id==typeID && !$0.archived}) else {throw MeterError("Выберите действующий тип из справочника")}}
            for id in Set(ids).sorted() {
                guard var task=try task(id) else {throw MeterError("Задача больше не существует")}
                task.typeID=typeID
                try saveTask(task)
            }
        }
    }
    public func deleteTaskType(_ id:String) throws {
        try transaction {
            guard try taskTypes().contains(where:{$0.id==id}) else {throw MeterError("Тип больше не существует")}
            for var task in try tasks() where task.typeID==id {
                if task.legacyKind==nil {task.legacyKind=task.kind}
                task.typeID=nil;task.kind=""
                try saveTask(task)
            }
            try exec("DELETE FROM task_types WHERE id=?",[id])
        }
    }
    func resolveType(_ task:WorkTask,types:[TaskType])->WorkTask {
        var task=task
        if let id=task.typeID {
            if let type=types.first(where:{$0.id==id}) {task.kind=type.name}
            else {task.typeID=nil}
        }
        return task
    }
}
