import Foundation

@MainActor
final class JupyterMonitor: ObservableObject {
    static let shared = JupyterMonitor()

    @Published private(set) var connectionState: JupyterConnectionState = .searching
    @Published private(set) var currentExecution: JupyterExecutionSnapshot?
    @Published private(set) var busyKernelCount = 0
    @Published private(set) var sessionCount = 0
    @Published private(set) var displayedKernelMetrics: JupyterKernelMetrics?

    private struct SessionBinding {
        let server: JupyterServerInfo
        let session: JupyterSession
    }

    private struct NotebookWidget {
        var modelName = ""
        var minimum: Double = 0
        var maximum: Double = 1
        var value: Double = 0
        var textValue: String?
        var children: [String] = []

        var fraction: Double? {
            guard modelName.contains("Progress"), maximum > minimum else { return nil }
            return min(max((value - minimum) / (maximum - minimum), 0), 1)
        }
    }

    private let discovery = JupyterServerDiscovery()
    private let resourceMonitor = JupyterKernelResourceMonitor()
    private var monitorTask: Task<Void, Never>?
    private var resourceMonitorTask: Task<Void, Never>?
    private var connections: [String: JupyterKernelConnection] = [:]
    private var sessionsByKernel: [String: JupyterSession] = [:]
    private var executions: [String: JupyterExecutionSnapshot] = [:]
    private var pendingBusyStart: [String: Date] = [:]
    private var widgets: [String: NotebookWidget] = [:]

    init(startAutomatically: Bool = true) {
        if startAutomatically {
            start()
            startResourceMonitoring()
        }
    }

    func start() {
        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshConnections()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func startResourceMonitoring() {
        guard resourceMonitorTask == nil else { return }

        resourceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshKernelMetrics()

                // Memory can change quickly while a cell is executing. Keep the
                // idle polling inexpensive, but refresh the visible kernel four
                // times per second while it is working.
                let interval: Duration =
                    self.busyKernelCount > 0
                    ? .milliseconds(250)
                    : .seconds(1)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refreshKernelMetrics() async {
        if currentExecution?.phase == .completed {
            return
        }

        let kernelIDs = Set(executions.values.map(\.kernelID))
        let metrics = await resourceMonitor.sample(kernelIDs: kernelIDs)

        if let activeKernelID = currentExecution?.kernelID {
            displayedKernelMetrics = metrics[activeKernelID]
        } else {
            displayedKernelMetrics = nil
        }
    }

    private func refreshKernelMetricsNow() {
        Task { [weak self] in
            await self?.refreshKernelMetrics()
        }
    }

    private func refreshConnections() async {
        let servers = await discovery.discoverServers()

        guard !servers.isEmpty else {
            disconnectAll()
            connectionState = .noServer
            sessionCount = 0
            return
        }

        var bindings: [SessionBinding] = []
        var authenticationRequired = false
        var lastError: Error?

        for server in servers {
            do {
                let sessions = try await discovery.fetchSessions(from: server)
                bindings.append(contentsOf: sessions.map { SessionBinding(server: server, session: $0) })
            } catch JupyterServerDiscovery.DiscoveryError.authenticationRequired {
                authenticationRequired = true
            } catch {
                lastError = error
            }
        }

        let uniqueBindings = Dictionary(
            bindings.map { ($0.session.kernel.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let activeKernelIDs = Set(uniqueBindings.keys)
        for kernelID in connections.keys where !activeKernelIDs.contains(kernelID) {
            connections.removeValue(forKey: kernelID)?.stop()
            sessionsByKernel.removeValue(forKey: kernelID)
            removeState(for: kernelID)
        }

        for (kernelID, binding) in uniqueBindings {
            sessionsByKernel[kernelID] = binding.session
            guard connections[kernelID] == nil else { continue }

            let connection = JupyterKernelConnection(
                server: binding.server,
                kernelID: kernelID,
                onMessage: { [weak self] message in
                    self?.handle(message, kernelID: kernelID)
                },
                onDisconnect: { [weak self] disconnectedKernelID in
                    self?.handleDisconnect(kernelID: disconnectedKernelID)
                }
            )
            connections[kernelID] = connection
            connection.start()
        }

        sessionCount = uniqueBindings.count
        if !uniqueBindings.isEmpty {
            connectionState = .connected(sessionCount: uniqueBindings.count)
        } else if authenticationRequired {
            connectionState = .authenticationRequired
        } else if let lastError {
            connectionState = .unavailable(lastError.localizedDescription)
        } else {
            connectionState = .noSession
        }
    }

    func handle(_ message: JupyterKernelMessage, kernelID: String) {
        guard message.channel == nil || message.channel == "iopub" else { return }

        let messageID = message.parentMessageID.map { executionKey(kernelID: kernelID, messageID: $0) }

        switch message.messageType {
        case "status":
            guard
                let state = message.content["execution_state"] as? String,
                let messageID
            else {
                return
            }

            if state == "busy" {
                pendingBusyStart[messageID] = Date()
                refreshKernelMetricsNow()
            } else if state == "idle" {
                finishExecution(key: messageID)
                pendingBusyStart.removeValue(forKey: messageID)
                refreshKernelMetricsNow()
            }

        case "execute_input":
            guard let messageID else { return }
            let code = message.content["code"] as? String ?? ""
            let count = number(message.content["execution_count"]).map(Int.init)
            beginExecution(
                key: messageID,
                kernelID: kernelID,
                executionCount: count,
                code: code
            )

        case "error":
            guard let messageID, var execution = executions[messageID] else { return }
            let name = message.content["ename"] as? String ?? "Error"
            let value = message.content["evalue"] as? String ?? ""
            execution.phase = .failed(value.isEmpty ? name : "\(name): \(value)")
            executions[messageID] = execution
            publishIfCurrent(execution)

        case "stream", "display_data", "update_display_data", "execute_result":
            guard let update = progressUpdate(in: message.content) else { return }
            updateProgress(
                update.fraction,
                details: update.details,
                count: update.count,
                description: update.description,
                kernelID: kernelID,
                preferredKey: messageID
            )

        case "comm_open":
            updateWidget(from: message.content, kernelID: kernelID, isOpening: true)

        case "comm_msg":
            updateWidget(from: message.content, kernelID: kernelID, isOpening: false)

        case "comm_close":
            if let commID = message.content["comm_id"] as? String {
                widgets.removeValue(forKey: widgetKey(kernelID: kernelID, commID: commID))
            }

        default:
            break
        }
    }

    private func beginExecution(
        key: String,
        kernelID: String,
        executionCount: Int?,
        code: String
    ) {
        discardCompletedExecution()

        let summary =
            code
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !isCommentDivider($0) }) ?? "Cell running"

        let snapshot = JupyterExecutionSnapshot(
            messageID: key,
            kernelID: kernelID,
            notebookPath: sessionsByKernel[kernelID]?.path ?? "Notebook",
            executionCount: executionCount,
            codeSummary: String(summary.prefix(120)),
            startedAt: pendingBusyStart[key] ?? Date(),
            phase: .running
        )

        executions[key] = snapshot
        currentExecution = snapshot
        updateBusyKernelCount()
        NotificationCenter.default.post(name: .jupyterExecutionDidStart, object: nil)
    }

    private func isCommentDivider(_ line: String) -> Bool {
        guard line.hasPrefix("#") else { return false }
        let comment =
            line
            .dropFirst()
            .trimmingCharacters(in: .whitespaces)
        return comment.count >= 3 && comment.allSatisfy { $0 == "=" }
    }

    private func finishExecution(key: String) {
        guard var execution = executions.removeValue(forKey: key) else { return }

        pendingBusyStart.removeValue(forKey: key)
        execution.phase = .completed
        execution.finishedAt = Date()

        if executions.isEmpty {
            currentExecution = execution
        } else if currentExecution?.messageID == key {
            currentExecution = mostRecentActiveExecution()
        }
        let retainsCompletedExecution =
            currentExecution?.messageID == execution.messageID
            && currentExecution?.phase == .completed
        if !retainsCompletedExecution {
            removeWidgets(for: execution.kernelID)
            if !executions.values.contains(where: { $0.kernelID == execution.kernelID }) {
                discardResourceState(for: execution.kernelID)
            }
        }
        updateBusyKernelCount()
        if !retainsCompletedExecution {
            refreshKernelMetricsNow()
        }
        NotificationCenter.default.post(name: .jupyterExecutionDidFinish, object: nil)
    }

    private func updateProgress(
        _ progress: Double,
        details: String?,
        count: String?,
        description: String?,
        kernelID: String,
        preferredKey: String?
    ) {
        let key =
            preferredKey.flatMap { executions[$0] != nil ? $0 : nil }
            ?? executions.values
            .filter { $0.kernelID == kernelID && $0.phase == .running }
            .max(by: { $0.startedAt < $1.startedAt })?
            .messageID

        guard let key, var execution = executions[key] else { return }
        execution.progress = min(max(progress, 0), 1)
        if let details {
            execution.progressDetails = details
        }
        if let count {
            execution.progressCount = count
        }
        if let description {
            execution.progressDescription = description
        }
        executions[key] = execution
        publishIfCurrent(execution)
    }

    private func updateWidget(
        from content: [String: Any],
        kernelID: String,
        isOpening: Bool
    ) {
        guard
            let commID = content["comm_id"] as? String,
            let data = content["data"] as? [String: Any],
            let state = data["state"] as? [String: Any]
        else {
            return
        }

        let key = widgetKey(kernelID: kernelID, commID: commID)
        var widget = widgets[key] ?? NotebookWidget()

        if let modelName = state["_model_name"] as? String {
            widget.modelName = modelName
        }
        if let minimum = number(state["min"]) {
            widget.minimum = minimum
        }
        if let maximum = number(state["max"]) {
            widget.maximum = maximum
        }
        if let value = number(state["value"]) {
            widget.value = value
        }
        if let value = state["value"] as? String {
            widget.textValue = value
        }
        if let children = state["children"] as? [String] {
            widget.children = children.map(widgetCommID(from:))
        }

        // The HTML labels and HBox are as important as FloatProgress for
        // tqdm.notebook. Cache every widget opened by Jupyter so their model
        // references can be correlated even when messages arrive out of order.
        if isOpening || widgets[key] != nil {
            widgets[key] = widget
        }

        if widgets[key] != nil {
            publishNotebookProgress(
                kernelID: kernelID,
                changedCommID: commID
            )
        } else if let fraction = widget.fraction {
            updateProgress(
                fraction,
                details: nil,
                count: nil,
                description: nil,
                kernelID: kernelID,
                preferredKey: nil
            )
        }
    }

    private func publishNotebookProgress(
        kernelID: String,
        changedCommID: String
    ) {
        let kernelPrefix = "\(kernelID):"
        let containers =
            widgets
            .filter { key, widget in
                key.hasPrefix(kernelPrefix)
                    && !widget.children.isEmpty
                    && (key == widgetKey(kernelID: kernelID, commID: changedCommID)
                        || widget.children.contains(changedCommID))
            }
            .map(\.value)

        for container in containers {
            let children = container.children.compactMap { commID in
                widgets[widgetKey(kernelID: kernelID, commID: commID)]
            }
            guard
                let progressIndex = children.firstIndex(where: { $0.fraction != nil }),
                let fraction = children[progressIndex].fraction
            else {
                continue
            }

            let leftText = children[..<progressIndex]
                .compactMap(\.textValue)
                .last
            let rightText = children[(progressIndex + 1)...]
                .compactMap(\.textValue)
                .first
                .map(decodedWidgetText)
            let countMatch = rightText.flatMap {
                lastTwoCaptures(in: $0, pattern: #"(\d+)\s*/\s*(\d+)"#)
            }

            updateProgress(
                fraction,
                details: rightText.flatMap(tqdmDetails(in:)),
                count: countMatch.map { "\($0.0)/\($0.1)" },
                description: leftText.flatMap(notebookWidgetDescription(in:)),
                kernelID: kernelID,
                preferredKey: nil
            )
        }
    }

    private func widgetCommID(from modelReference: String) -> String {
        let prefix = "IPY_MODEL_"
        return modelReference.hasPrefix(prefix)
            ? String(modelReference.dropFirst(prefix.count))
            : modelReference
    }

    private func notebookWidgetDescription(in htmlText: String) -> String? {
        var description = decodedWidgetText(htmlText)
        description = description.replacingOccurrences(
            of: #"\s*:?[\s\u2007]*\d{1,3}(?:\.\d+)?\s*%.*$"#,
            with: "",
            options: .regularExpression
        )
        description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.hasSuffix(":") {
            description.removeLast()
        }
        description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    private func decodedWidgetText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2007}", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private struct ProgressUpdate {
        let fraction: Double
        let details: String?
        let count: String?
        let description: String?
    }

    private func progressUpdate(in content: [String: Any]) -> ProgressUpdate? {
        var candidates: [String] = []

        if let text = content["text"] as? String {
            candidates.append(text)
        }
        if let data = content["data"] as? [String: Any],
            let plainText = data["text/plain"] as? String
        {
            candidates.append(plainText)
        }

        for text in candidates.reversed() {
            let details = tqdmDetails(in: text)
            let countMatch = lastTwoCaptures(in: text, pattern: #"(\d+)\s*/\s*(\d+)"#)
            let count = countMatch.map { "\($0.0)/\($0.1)" }
            let description = tqdmDescription(in: text)

            if let percentage = lastCapture(in: text, pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#),
                let value = Double(percentage)
            {
                return ProgressUpdate(
                    fraction: min(max(value / 100, 0), 1),
                    details: details,
                    count: count,
                    description: description
                )
            }

            if let match = countMatch,
                let current = Double(match.0),
                let total = Double(match.1),
                total > 0,
                current <= total
            {
                return ProgressUpdate(
                    fraction: current / total,
                    details: details,
                    count: count,
                    description: description
                )
            }
        }

        return nil
    }

    private func tqdmDetails(in text: String) -> String? {
        let pattern = #"\[[^\]\r\n]*<\s*([^,\]\r\n]+)\s*,\s*([^\]\r\n]+)\]"#
        guard let match = lastTwoCaptures(in: text, pattern: pattern) else { return nil }

        let remaining = match.0.trimmingCharacters(in: .whitespacesAndNewlines)
        var rate = match.1.trimmingCharacters(in: .whitespacesAndNewlines)
        rate = rate.replacingOccurrences(
            of: #"(\d)([A-Za-z])"#,
            with: "$1 $2",
            options: .regularExpression
        )

        guard !remaining.isEmpty, !rate.isEmpty else { return nil }
        return "ETA \(remaining) · \(rate)"
    }

    private func tqdmDescription(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let percentagePattern = #"\d{1,3}(?:\.\d+)?\s*%\|"#
        guard let regex = try? NSRegularExpression(pattern: percentagePattern) else { return nil }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            var line = String(rawLine)
            line = line.replacingOccurrences(
                of: #"\u001B\[[0-?]*[ -/]*[@-~]"#,
                with: "",
                options: .regularExpression
            )

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let match = regex.firstMatch(in: line, range: range),
                let matchRange = Range(match.range, in: line)
            else {
                continue
            }

            var description = String(line[..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if description.hasSuffix(":") {
                description.removeLast()
            }
            description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return description.isEmpty ? nil : description
        }

        return nil
    }

    private func lastCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.matches(in: text, range: range).last,
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    private func lastTwoCaptures(in text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.matches(in: text, range: range).last,
            match.numberOfRanges > 2,
            let firstRange = Range(match.range(at: 1), in: text),
            let secondRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }
        return (String(text[firstRange]), String(text[secondRange]))
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string)
        default:
            nil
        }
    }

    private func publishIfCurrent(_ execution: JupyterExecutionSnapshot) {
        if currentExecution?.messageID == execution.messageID {
            currentExecution = execution
        }
    }

    private func updateBusyKernelCount() {
        busyKernelCount =
            Set(
                executions.values.map(\.kernelID)
            ).count
    }

    var activeExecutionCount: Int {
        executions.count
    }

    func discardCompletedExecution() {
        guard let execution = currentExecution,
            execution.phase == .completed
        else { return }
        currentExecution = nil
        removeWidgets(for: execution.kernelID)
        discardResourceState(for: execution.kernelID)
        refreshKernelMetricsNow()
    }

    private func mostRecentActiveExecution() -> JupyterExecutionSnapshot? {
        executions.values.max { $0.startedAt < $1.startedAt }
    }

    private func removeWidgets(for kernelID: String) {
        widgets = widgets.filter { !$0.key.hasPrefix("\(kernelID):") }
    }

    private func discardResourceState(for kernelID: String) {
        if displayedKernelMetrics?.kernelID == kernelID {
            displayedKernelMetrics = nil
        }
        Task { [resourceMonitor] in
            await resourceMonitor.discard(kernelID: kernelID)
        }
    }

    private func executionKey(kernelID: String, messageID: String) -> String {
        "\(kernelID):\(messageID)"
    }

    private func widgetKey(kernelID: String, commID: String) -> String {
        "\(kernelID):\(commID)"
    }

    private func handleDisconnect(kernelID: String) {
        connections.removeValue(forKey: kernelID)?.stop()
        sessionsByKernel.removeValue(forKey: kernelID)
        removeState(for: kernelID)
    }

    private func removeState(for kernelID: String) {
        let removedActiveExecution = executions.values.contains { $0.kernelID == kernelID }
        let preservesCompletedExecution =
            currentExecution?.kernelID == kernelID
            && currentExecution?.phase == .completed
        executions = executions.filter { $0.value.kernelID != kernelID }
        if !preservesCompletedExecution {
            removeWidgets(for: kernelID)
            discardResourceState(for: kernelID)
        }
        pendingBusyStart = pendingBusyStart.filter { !$0.key.hasPrefix("\(kernelID):") }
        if currentExecution?.kernelID == kernelID,
            currentExecution?.phase != .completed
        {
            currentExecution = mostRecentActiveExecution()
        }
        updateBusyKernelCount()
        if removedActiveExecution {
            NotificationCenter.default.post(
                name: .jupyterExecutionDidFinish,
                object: nil,
                userInfo: ["showCompletion": false]
            )
        }
    }

    private func disconnectAll() {
        let hadActiveExecutions = !executions.isEmpty
        let completedExecution =
            currentExecution?.phase == .completed
            ? currentExecution
            : nil
        for connection in connections.values {
            connection.stop()
        }
        connections.removeAll()
        sessionsByKernel.removeAll()
        executions.removeAll()
        pendingBusyStart.removeAll()
        currentExecution = completedExecution
        busyKernelCount = 0
        if completedExecution == nil {
            widgets.removeAll()
            displayedKernelMetrics = nil
            Task { [resourceMonitor] in
                await resourceMonitor.discardAll()
            }
        }
        if hadActiveExecutions {
            NotificationCenter.default.post(
                name: .jupyterExecutionDidFinish,
                object: nil,
                userInfo: ["showCompletion": false]
            )
        }
    }
}
