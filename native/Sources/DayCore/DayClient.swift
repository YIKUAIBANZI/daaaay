import Foundation

public struct ServiceError: LocalizedError {
    public let code: Int
    public let message: String
    public var errorDescription: String? { message }
}

public struct MoveTaskResult: Decodable {
    public let source: DayDocument
    public let target: DayDocument
}

public actor DayClient {
    public let baseURL: URL
    private let session: URLSession
    private var token: String?

    public init(baseURL: URL = URL(string:"http://127.0.0.1:18765")!) {
        precondition(baseURL.scheme == "http" && baseURL.host == "127.0.0.1", "Only the local service is supported")
        self.baseURL=baseURL
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=5; config.timeoutIntervalForResource=8
        self.session=URLSession(configuration:config)
    }
    public func bootstrap() async throws {
        struct Bootstrap: Decodable { let token: String }
        let data=try await request("/api/bootstrap")
        token=try JSONDecoder().decode(Bootstrap.self,from:data).token
    }
    public func read(_ day: String) async throws -> DayDocument {
        let data=try await request("/api/day?date="+day)
        return try JSONDecoder().decode(DayDocument.self,from:data)
    }
    public func save(_ document: DayDocument) async throws -> DayDocument {
        struct Body: Encodable { let date: String; let revision: Int; let tasks: [DayTask]; let source="native_user" }
        let body=try JSONEncoder().encode(Body(date:document.date,revision:document.revision,tasks:document.tasks))
        let data=try await post("/api/day",body:body)
        return try JSONDecoder().decode(DayDocument.self,from:data)
    }
    public func moveTask(_ task: DayTask, from source: String, to target: String,
                         sourceRevision: Int, targetRevision: Int) async throws -> MoveTaskResult {
        struct Body: Encodable {
            let sourceDate: String
            let targetDate: String
            let taskId: String
            let sourceRevision: Int
            let targetRevision: Int
            let task: DayTask
            let source="native_user"
        }
        let body=try JSONEncoder().encode(Body(sourceDate:source,targetDate:target,taskId:task.id,
                                               sourceRevision:sourceRevision,targetRevision:targetRevision,task:task))
        let data=try await post("/api/task/move",body:body)
        return try JSONDecoder().decode(MoveTaskResult.self,from:data)
    }
    public func calendar(_ day: String) async throws -> Data { try await request("/api/calendar?date="+day) }

    private func post(_ path: String, body: Data) async throws -> Data {
        if token == nil { try await bootstrap() }
        do { return try await request(path,body:body) }
        catch let e as ServiceError where e.code == 403 {
            // A service restart rotates the token. A rejected request was not applied.
            try await bootstrap()
            return try await request(path,body:body)
        }
    }
    private func request(_ path: String, body: Data? = nil) async throws -> Data {
        let url=URL(string:path,relativeTo:baseURL)!.absoluteURL
        var req=URLRequest(url:url)
        if let body {
            req.httpMethod="POST"; req.httpBody=body
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            req.setValue(baseURL.absoluteString.trimmingCharacters(in:CharacterSet(charactersIn:"/")),forHTTPHeaderField:"Origin")
            req.setValue(token,forHTTPHeaderField:"X-Daaaay-Token")
        }
        let (data,response)=try await session.data(for:req)
        let code=(response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            struct Failure: Decodable { let error: String }
            let msg=(try? JSONDecoder().decode(Failure.self,from:data).error) ?? "本机服务暂时不可用（\(code)）"
            throw ServiceError(code:code,message:msg)
        }
        return data
    }
}
