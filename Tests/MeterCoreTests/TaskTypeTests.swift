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
        XCTAssertEqual(try db.taskTypes().count,6)
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
}
