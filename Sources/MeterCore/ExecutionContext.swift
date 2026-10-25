import Foundation

/// Recorded evidence only. Never backfill a historical run from today's configuration.
public struct ExecutionConfiguration:Codable {
    public var model:String
    public var effort:String
    public var provider:String?
    public var serviceTier:String?
    public var contextWindow:Int?
    public var tokens:TokenCount = .init()
    public init(model:String="",effort:String="",provider:String?=nil,serviceTier:String?=nil,contextWindow:Int?=nil) {
        self.model=model;self.effort=effort;self.provider=provider;self.serviceTier=serviceTier;self.contextWindow=contextWindow
    }
    public func sameSettings(as other:Self)->Bool {
        model==other.model && effort==other.effort && provider==other.provider && serviceTier==other.serviceTier && contextWindow==other.contextWindow
    }
}

public struct ExecutionToolCall:Codable,Identifiable {
    public var id:String
    public var name:String
    public var server:String?
    public var status:String
    public var completedAt:Date?
    public var duration:Double?
    public init(id:String,name:String,server:String?=nil,status:String,completedAt:Date?=nil,duration:Double?=nil) {
        self.id=id;self.name=name;self.server=server;self.status=status;self.completedAt=completedAt;self.duration=duration
    }
}

public struct ExecutionContext:Codable {
    public var originator:String?
    public var clientVersion:String?
    public var source:String?
    public var configurations:[ExecutionConfiguration] = []
    public var calls:[ExecutionToolCall] = []
    public init(originator:String?=nil,clientVersion:String?=nil,source:String?=nil) {
        self.originator=originator;self.clientVersion=clientVersion;self.source=source
    }
    public var harness:String { [originator,clientVersion].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" ") }
    public mutating func record(_ configuration:ExecutionConfiguration) {
        if configurations.last?.sameSettings(as:configuration) != true {configurations.append(configuration)}
    }
    public mutating func add(_ tokens:TokenCount) {
        guard !configurations.isEmpty else{return}
        configurations[configurations.count-1].tokens=configurations[configurations.count-1].tokens+tokens
    }
    public mutating func record(_ call:ExecutionToolCall) {
        if let index=calls.firstIndex(where:{$0.id==call.id}) {calls[index]=call} else {calls.append(call)}
    }
}
