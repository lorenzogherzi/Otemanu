import Darwin
import Foundation

actor JupyterServerDiscovery {
    enum DiscoveryError: LocalizedError {
        case invalidURL
        case authenticationRequired
        case serverRejected(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid Jupyter server URL"
            case .authenticationRequired:
                "The Jupyter server requires authentication"
            case .serverRejected(let status):
                "The Jupyter server responded with status \(status)"
            }
        }
    }

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    func discoverServers() -> [JupyterServerInfo] {
        var candidates: [(server: JupyterServerInfo, modifiedAt: Date)] = []

        for directory in runtimeDirectories() {
            guard
                let files = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
            else {
                continue
            }

            for file in files where isServerInfoFile(file) {
                guard
                    let data = try? Data(contentsOf: file),
                    let server = try? JSONDecoder().decode(JupyterServerInfo.self, from: data),
                    isProcessAlive(server.pid)
                else {
                    continue
                }

                let date =
                    (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                candidates.append((server, date))
            }
        }

        var newestServerByURL: [String: (JupyterServerInfo, Date)] = [:]
        for candidate in candidates {
            let current = newestServerByURL[candidate.server.url]
            if current == nil || candidate.modifiedAt > current!.1 {
                newestServerByURL[candidate.server.url] = (candidate.server, candidate.modifiedAt)
            }
        }

        return newestServerByURL.values
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func fetchSessions(from server: JupyterServerInfo) async throws -> [JupyterSession] {
        guard let baseURL = URL(string: server.url) else {
            throw DiscoveryError.invalidURL
        }

        let endpoint = baseURL.appendingPathComponent("api/sessions")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let token = server.token, !token.isEmpty {
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.serverRejected(-1)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw DiscoveryError.authenticationRequired
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DiscoveryError.serverRejected(httpResponse.statusCode)
        }

        return try decoder.decode([JupyterSession].self, from: data)
    }

    private func runtimeDirectories() -> [URL] {
        var paths: [String] = []

        if let configured = ProcessInfo.processInfo.environment["JUPYTER_RUNTIME_DIR"] {
            paths.append(configured)
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        paths.append("\(home)/Library/Jupyter/runtime")
        paths.append("\(home)/.local/share/jupyter/runtime")
        paths.append("\(home)/.jupyter/runtime")

        var seen = Set<String>()
        return
            paths
            .filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func isServerInfoFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return url.pathExtension == "json"
            && (name.hasPrefix("jpserver-") || name.hasPrefix("nbserver-"))
    }

    private func isProcessAlive(_ pid: Int?) -> Bool {
        guard let pid, pid > 0 else { return true }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}
