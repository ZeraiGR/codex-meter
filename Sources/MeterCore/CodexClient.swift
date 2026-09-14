import Foundation
import CryptoKit

public struct CodexServiceError: LocalizedError {
    public let method: String
    public let code: Int
    public let message: String

    public init(method: String, code: Int, message: String) {
        self.method = method; self.code = code
        // Server diagnostics can contain request headers. Never copy credentials.
        self.message = message
            .replacingOccurrences(of: "(?i)bearer\\s+[^\\s,;]+", with: "Bearer [скрыто]", options: .regularExpression)
            .replacingOccurrences(of: "\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b", with: "[скрыто]", options: .regularExpression)
    }
    public var requiresLogin: Bool {
        let text = message.lowercased()
        return code == 401 || ["401 unauthorized", "status: 401", "status code 401", "not authenticated", "not logged in", "authentication required", "refresh_token", "token has expired"].contains { text.contains($0) }
    }
    public var retryable: Bool { !requiresLogin && [-32603, -32098, -32099].contains(code) }
    public var errorDescription: String? {
        let summary = requiresLogin
            ? "Codex не подтвердил вход в аккаунт. Откройте Codex и войдите снова, затем обновите данные."
            : "Не удалось обновить данные Codex. Последние полученные значения сохранены; обновление повторится автоматически."
        return summary + "\n\n\(method) · код \(code)\n\(message)"
    }
}

public final class CodexClient {
    public static func executable(db:Database) throws -> URL {
        if let custom=try db.value("codexPath"),!custom.isEmpty {
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:custom,isDirectory:&directory),!directory.boolValue,
                  FileManager.default.isExecutableFile(atPath:custom) else {
                throw MeterError("Выбранный файл Codex недоступен. Выберите его заново или включите автоматический поиск в дополнительных настройках.")
            }
            return URL(fileURLWithPath:custom)
        }
        // A menu-bar app does not inherit an interactive shell's nvm PATH.
        // Use the native executable directly, without depending on a Node shim.
        let nvm=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        let installed:[URL]=(try? FileManager.default.contentsOfDirectory(at:nvm,includingPropertiesForKeys:nil)) ?? []
        let versions=installed.sorted { $0.lastPathComponent.compare($1.lastPathComponent,options:.numeric) == .orderedDescending }
        #if arch(arm64)
        let vendor="lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
        #else
        let vendor="lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex"
        #endif
        for version in versions {let binary=version.appendingPathComponent(vendor);if FileManager.default.isExecutableFile(atPath:binary.path){return binary}}
        let candidates=["/Applications/Codex.app/Contents/Resources/codex","/Applications/ChatGPT.app/Contents/Resources/codex","/opt/homebrew/bin/codex","/usr/local/bin/codex"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath:candidate) { return URL(fileURLWithPath:candidate) }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator:":") {
            let url=URL(fileURLWithPath:String(dir)).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath:url.path) { return url }
        }
        throw MeterError("Codex не найден. Установите Codex или выберите его файл в дополнительных настройках.")
    }
    public static func fetch(db:Database) throws -> AccountSnapshot {
        for attempt in 0..<3 {
            do { return try fetchOnce(db:db) }
            catch let error as CodexServiceError where error.retryable && attempt < 2 {
                // A failed startup/connection needs a fresh app-server process.
                Thread.sleep(forTimeInterval:Double(attempt+1))
            }
        }
        preconditionFailure("Every fetch either returns a snapshot or throws")
    }
    private static func fetchOnce(db:Database) throws -> AccountSnapshot {
        let rpc=try RPC(executable:executable(db:db));defer{rpc.close()}
        _=try rpc.call("initialize",["clientInfo":["name":"codex_meter","title":"Codex Meter","version":"1.0.0"]])
        try rpc.notify("initialized",[:])
        let account=try rpc.call("account/read",["refreshToken":false])["account"] as? [String:Any]
        guard let account, account["type"] as? String == "chatgpt" else { throw MeterError("Войдите в Codex через подписку ChatGPT. Учёт API-ключей в эту версию не входит.") }
        let identity=(account["email"] as? String ?? "local")+"|"+(account["planType"] as? String ?? "unknown")
        let key=SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined()
        let limits=try rpc.call("account/rateLimits/read",[:])
        var buckets:[QuotaBucket]=[]
        if let byID=limits["rateLimitsByLimitId"] as? [String:Any] {
            for (id,value) in byID {
                let data=try JSONSerialization.data(withJSONObject:value)
                var bucket=try JSONDecoder().decode(QuotaBucket.self,from:data);bucket.limitId=id;buckets.append(bucket)
            }
        }
        if !buckets.contains(where:{$0.id=="codex"}),let legacy=limits["rateLimits"] as? [String:Any] {
            buckets.append(try JSONDecoder().decode(QuotaBucket.self,from:JSONSerialization.data(withJSONObject:legacy)))
        }
        var daily:[DailyUsage]?,lifetime:Int64?,usageError:String?
        do {
            let usage=try rpc.call("account/usage/read",[:])
            if let value=usage["dailyUsageBuckets"] as? [[String:Any]] {
                daily=try JSONDecoder().decode([DailyUsage].self,from:JSONSerialization.data(withJSONObject:value)).sorted{$0.startDate<$1.startDate}
            }
            lifetime=((usage["summary"] as? [String:Any])?["lifetimeTokens"] as? NSNumber)?.int64Value
        } catch { usageError="История аккаунта временно недоступна" }
        return AccountSnapshot(accountKey:key,plan:account["planType"] as? String ?? "ChatGPT",buckets:buckets.sorted{$0.id=="codex" && $1.id != "codex"},daily:daily,lifetimeTokens:lifetime,usageError:usageError)
    }
}

private final class RPC {
    private let process=Process(),input=Pipe(),output=Pipe(),condition=NSCondition()
    private var buffer=Data(),responses:[Int:[String:Any]]=[:],nextID=0,closed=false
    init(executable:URL) throws {
        process.executableURL=executable;process.arguments=["app-server","--stdio"]
        process.standardInput=input;process.standardOutput=output
        process.standardError=ProcessInfo.processInfo.environment["CODEX_METER_DEBUG"]=="1" ? FileHandle.standardError:FileHandle.nullDevice
        process.currentDirectoryURL=FileManager.default.temporaryDirectory
        var env=ProcessInfo.processInfo.environment
        env["PATH"]="\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"+(env["PATH"] ?? "")
        process.environment=env
        output.fileHandleForReading.readabilityHandler={ [weak self] handle in
            let data=handle.availableData
            guard let self else{return}
            self.condition.lock();defer{self.condition.unlock()}
            if data.isEmpty { self.closed=true;self.condition.broadcast();return }
            self.buffer.append(data)
            while let end=self.buffer.firstIndex(of:10) {
                let line=self.buffer.prefix(upTo:end);self.buffer.removeSubrange(...end)
                if let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let id=object["id"] as? Int {self.responses[id]=object}
            }
            self.condition.broadcast()
        }
        try process.run()
    }
    func notify(_ method:String,_ params:[String:Any]) throws { try write(["method":method,"params":params]) }
    private func write(_ message:[String:Any]) throws {
        var data=try JSONSerialization.data(withJSONObject:message);data.append(10)
        try input.fileHandleForWriting.write(contentsOf:data)
    }
    func call(_ method:String,_ params:[String:Any]) throws -> [String:Any] {
        nextID += 1;let id=nextID
        try write(["method":method,"params":params,"id":id])
        let deadline=Date().addingTimeInterval(12)
        condition.lock();defer{condition.unlock()}
        while responses[id]==nil && !closed {
            if !condition.wait(until:deadline) { throw CodexServiceError(method:method,code:-32098,message:"Превышено время ожидания ответа (12 секунд).") }
        }
        guard let response=responses.removeValue(forKey:id) else {throw CodexServiceError(method:method,code:-32099,message:"Codex завершил подключение до получения ответа.")}
        if let error=response["error"] as? [String:Any] {
            let code=error["code"] as? Int ?? 0
            throw CodexServiceError(method:method,code:code,message:error["message"] as? String ?? "Сервер не передал описание ошибки.")
        }
        return response["result"] as? [String:Any] ?? [:]
    }
    func close() {
        output.fileHandleForReading.readabilityHandler=nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
