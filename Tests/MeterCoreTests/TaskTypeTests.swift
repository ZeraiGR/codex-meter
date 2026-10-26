import Foundation
import MeterCore

extension MeterCoreTests {
    func testTaskTypeCatalogPreservesLegacyAndRenamesByIdentity() throws {
        let db=try database();defer{try? FileManager.default.removeItem(at:db.directory)}
        let task=WorkTask(id:"legacy",title:"Результат",kind:"project-docs")
        try db.saveTask(task)
        try db.saveRun(RunRecord(id:"run",thread:"thread",started:epoch,tokens:.init(input:123),taskID:task.id))
        XCTAssertNil(try db.task(task.id)?.typeID)
        XCTAssertEqual(try db.task(task.id)?.kind,"project-docs")
        XCTAssertEqual(try db.task(task.id)?.typeLabel,"Тип не указан")
        XCTAssertTrue(try db.taskTypes().isEmpty)
        try db.saveTaskType(TaskType(id:"documentation",name:"Документация"))
        try db.saveTaskType(TaskType(id:"review",name:"Ревью"))
        try db.assignTaskType([task.id],typeID:"documentation")
        XCTAssertEqual(try db.task(task.id)?.legacyKind,"project-docs")
        var type=try XCTUnwrap(try db.taskTypes().first{$0.id=="documentation"})
        type.name="Документы";try db.saveTaskType(type)
        XCTAssertEqual(try db.task(task.id)?.kind,"Документы")
        XCTAssertEqual(try db.summaries().first?.tokens.total,123)
        XCTAssertEqual(TaskListQuery.apply(try db.summaries(),kind:type.id).count,1)
        XCTAssertEqual(TaskListQuery.apply(try db.summaries(),kind:"Док").count,0)
        XCTAssertThrowsError(try db.saveTaskType(TaskType(name:"  документы  ")))
        XCTAssertThrowsError(try db.saveTaskType(TaskType(name:" \n")))
        type.archived=true;try db.saveTaskType(type)
        var saved=try XCTUnwrap(try db.task(task.id));saved.status="completed";try db.saveTask(saved)
        XCTAssertEqual(try db.task(task.id)?.typeID,type.id)
        try db.saveTask(WorkTask(id:"new",title:"Другая",kind:""))
        XCTAssertThrowsError(try db.assignTaskType(["new"],typeID:type.id))
        XCTAssertThrowsError(try db.assignTaskType(["new","missing"],typeID:"review"))
        XCTAssertNil(try db.task("new")?.typeID)
        XCTAssertEqual(TaskListQuery.apply(try db.summaries(),kind:"unclassified").map(\.id),["new"])
        type.archived=false;try db.saveTaskType(type)
        try db.assignTaskType(["new"],typeID:type.id)
        XCTAssertEqual(try Database(directory:db.directory).task("new")?.typeID,type.id)
    }

    func testSkillNeverImplicitlyClassifiesTaskAndForecastRequiresType() throws {
        let db=try database();defer{try? FileManager.default.removeItem(at:db.directory)}
        try db.saveTaskType(TaskType(id:"review",name:"Ревью"))
        let base=["task-start","--thread","t","--turn","one","--title","Результат"]
        let old=try Codec.decode(WorkTask.self,Commands.run(base+["--kind","review"],directory:db.directory))
        XCTAssertNil(old.typeID)
        let reused=try Codec.decode(WorkTask.self,Commands.run(base+["--skill","other-skill"],directory:db.directory))
        XCTAssertEqual(old.id,reused.id)
        _=try Commands.run(["task-end","--id",old.id],directory:db.directory)
        let fresh=try Codec.decode(WorkTask.self,Commands.run(base+["--skill","project-docs"],directory:db.directory))
        XCTAssertEqual(fresh.skill,"project-docs");XCTAssertNil(fresh.typeID)
        try db.assignTaskType([fresh.id],typeID:"review")
        let resumed=try Codec.decode(WorkTask.self,Commands.run(base+["--kind","different-skill"],directory:db.directory))
        XCTAssertEqual(resumed.id,fresh.id);XCTAssertEqual(resumed.typeID,"review")
        let json=try Commands.run(["forecast","--kind","review"],directory:db.directory)
        let forecast=try Codec.decode(Forecast.self,json)
        XCTAssertEqual(forecast.samples,0);XCTAssertEqual(forecast.risk,"unknown")
        XCTAssertThrowsError(try Commands.run(["task-start","--thread","different","--turn","turn","--title","Different","--type-id","missing"],directory:db.directory))
        let hook=try Commands.run(["hook"],directory:db.directory,input:Data("{\"session_id\":\"t\",\"turn_id\":\"next\"}".utf8))
        XCTAssertFalse(hook.contains("--kind <skill-name>"));XCTAssertTrue(hook.contains("A skill is NOT a task type"))
    }
    func testDeletingTaskTypePreservesHistoryAndStaysEmptyOnReopen() throws {
        let db=try database();defer{try? FileManager.default.removeItem(at:db.directory)}
        XCTAssertTrue(try db.taskTypes().isEmpty)
        let type=TaskType(id:"custom",name:"Мой тип")
        try db.saveTaskType(type)
        for id in ["one","two"] {
            var task=WorkTask(id:id,title:id,kind:"",status:"completed",created:epoch,finished:epoch)
            task.typeID=type.id;try db.saveTask(task)
        }
        try db.saveRun(RunRecord(id:"run",thread:"thread",started:epoch,tokens:.init(input:123),taskID:"one"))
        let before=try db.query("SELECT * FROM turns ORDER BY id")
        try db.exec("CREATE TRIGGER reject_type_clear BEFORE UPDATE ON tasks WHEN NEW.id='two' BEGIN SELECT RAISE(ABORT,'test failure'); END")
        XCTAssertThrowsError(try db.deleteTaskType(type.id))
        XCTAssertEqual(try db.task("one")?.typeID,type.id)
        XCTAssertEqual(try db.taskTypes(),[type])
        try db.exec("DROP TRIGGER reject_type_clear")
        try db.deleteTaskType(type.id)
        XCTAssertTrue(try db.taskTypes().isEmpty)
        XCTAssertEqual(try db.tasks().count,2)
        XCTAssertNil(try db.task("one")?.typeID)
        XCTAssertEqual(try db.task("one")?.legacyKind,type.name)
        XCTAssertEqual(try db.task("one")?.status,"completed")
        XCTAssertEqual(try db.task("one")?.created,epoch)
        XCTAssertEqual(try db.task("one")?.finished,epoch)
        XCTAssertEqual(try db.query("SELECT * FROM turns ORDER BY id"),before)
        XCTAssertEqual(try db.summaries().first{$0.id=="one"}?.tokens.total,123)
        let reopened=try Database(directory:db.directory)
        XCTAssertTrue(try reopened.taskTypes().isEmpty)
        XCTAssertNil(try reopened.task("one")?.typeID)
        XCTAssertThrowsError(try reopened.assignTaskType(["one"],typeID:type.id))
        XCTAssertThrowsError(try reopened.deleteTaskType(type.id))
    }

}
