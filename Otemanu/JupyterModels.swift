import Foundation

struct JupyterServerInfo: Decodable {
    let url: String
    let token: String?
    let pid: Int?
}

struct JupyterSession: Decodable {
    let path: String
    let kernel: JupyterKernel
}

struct JupyterKernel: Decodable {
    let id: String
}

struct JupyterKernelMessage {
    let channel: String?
    let messageType: String
    let parentMessageID: String?
    let content: [String: Any]

    init?(data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let header = dictionary["header"] as? [String: Any],
            let messageType = header["msg_type"] as? String
        else {
            return nil
        }

        let parentHeader = dictionary["parent_header"] as? [String: Any]
        channel = dictionary["channel"] as? String
        self.messageType = messageType
        parentMessageID = parentHeader?["msg_id"] as? String
        content = dictionary["content"] as? [String: Any] ?? [:]
    }
}

struct JupyterExecutionSnapshot: Equatable {
    enum Phase: Equatable {
        case running
        case failed(String)
        case completed
    }

    let messageID: String
    let kernelID: String
    var notebookPath: String
    var executionCount: Int?
    var codeSummary: String
    var startedAt: Date
    var finishedAt: Date? = nil
    var phase: Phase
    var progress: Double? = nil
    var progressDetails: String? = nil
    var progressCount: String? = nil
    var progressDescription: String? = nil

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

enum JupyterConnectionState: Equatable {
    case searching
    case noServer
    case noSession
    case connected(sessionCount: Int)
    case authenticationRequired
    case unavailable(String)
}

extension Notification.Name {
    static let jupyterExecutionDidStart = Notification.Name("Otemanu.jupyterExecutionDidStart")
    static let jupyterExecutionDidFinish = Notification.Name("Otemanu.jupyterExecutionDidFinish")
}
