import Foundation

extension Database {
    public func updateTaskStatuses(_ ids:[String],status:String) throws {
        guard ["active","paused","ongoing","completed","cancelled","failed"].contains(status) else {throw MeterError("Неизвестный статус задачи")}
        try transaction {
            let tasks=try selectedTasks(ids),now=Date()
            for var task in tasks {
                guard task.status != status else {continue}
                task.status=status
                task.finished=["active","paused","ongoing"].contains(status) ? nil:now
                try saveTask(task)
            }
        }
    }

    public func mergeTasks(sources:[String],target:String) throws {
        try transaction {
            let tasks=try selectedTasks(sources)
            guard try task(target) != nil else {throw MeterError("Задача назначения не найдена")}
            let others=tasks.filter{$0.id != target}
            guard !others.isEmpty else {throw MeterError("Выберите хотя бы одну другую задачу")}
            for task in others {try mergeTasks(source:task.id,target:target)}
        }
    }

    private func selectedTasks(_ ids:[String]) throws -> [WorkTask] {
        guard !ids.isEmpty else {throw MeterError("Выберите задачи")}
        return try Set(ids).sorted().map {id in
            guard let value=try task(id) else {throw MeterError("Одна из выбранных задач больше не существует. Обновите список.")}
            return value
        }
    }
}
