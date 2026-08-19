import SwiftUI

struct JupyterBusyCompactView: View {
    @ObservedObject private var monitor = JupyterMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.orange)
                .frame(width: 6, height: 6)

            Text("busy")
                .foregroundStyle(.orange)

            if let execution = monitor.currentExecution {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatDuration(execution.duration))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .foregroundStyle(.white)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct JupyterMonitorView: View {
    @ObservedObject private var monitor = JupyterMonitor.shared
    let topInset: CGFloat
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: min(topInset, proxy.size.height))

                    Group {
                        if let execution = monitor.currentExecution {
                            executionView(execution)
                        } else {
                            connectionView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    Color.clear
                        .frame(height: 8)
                }

                Group {
                    if let execution = monitor.currentExecution {
                        executionIndicator(execution)
                    } else {
                        connectionIndicator
                    }
                }
                .padding(.top, max(6, (topInset - 12) / 2))

                if let metrics = monitor.displayedKernelMetrics {
                    resourceIndicator(metrics)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, max(4, (topInset - 20) / 2))
                }

            }
            .padding(.horizontal, horizontalInset)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .foregroundStyle(.white)
        .animation(.smooth(duration: 0.25), value: monitor.currentExecution)
        .animation(.smooth(duration: 0.25), value: monitor.connectionState)
    }

    private func executionView(_ execution: JupyterExecutionSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                executionIcon(execution)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if let count = execution.executionCount {
                            Text("In [\(count)]")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Text(notebookName(execution.notebookPath))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11, weight: .semibold))

                    Text(execution.codeSummary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }

            if case .running = execution.phase {
                progressView(
                    execution.progress,
                    description: execution.progressDescription,
                    count: execution.progressCount,
                    details: execution.progressDetails
                )
            } else {
                resultLabel(execution)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func executionIcon(_ execution: JupyterExecutionSnapshot) -> some View {
        switch execution.phase {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.orange)
                .frame(width: 22, height: 22)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 21))
                .foregroundStyle(.red)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21))
                .foregroundStyle(.green)
        }
    }

    private func progressView(
        _ progress: Double?,
        description: String?,
        count: String?,
        details: String?
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                if let progress {
                    CompactProgressBar(value: progress)
                        .frame(maxWidth: .infinity)

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                } else {
                    CompactProgressBar(value: nil)
                        .frame(maxWidth: .infinity)

                    Text("busy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            if description != nil || count != nil || details != nil {
                HStack(spacing: 6) {
                    if let description {
                        Text(description)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }

                    Text([count, details].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func resultLabel(_ execution: JupyterExecutionSnapshot) -> some View {
        Group {
            switch execution.phase {
            case .failed(let failure):
                VStack(spacing: 1) {
                    Text("Cell failed")
                        .font(.system(size: 10, weight: .semibold))

                    Text(failure.summary)
                        .font(.system(size: 8.5, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            case .completed:
                Text("Cell complete")
                    .foregroundStyle(.green)
            case .running:
                EmptyView()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .frame(maxWidth: .infinity)
    }

    private var connectionView: some View {
        HStack(spacing: 9) {
            Image(systemName: connectionIcon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(connectionSubtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func durationView(_ execution: JupyterExecutionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(formatDuration(execution.duration))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func executionIndicator(_ execution: JupyterExecutionSnapshot) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(shortExecutionStatus(execution))
                .foregroundStyle(statusColor)

            durationView(execution)
        }
        .font(.system(size: 9, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusLabel)
                .foregroundStyle(statusColor)
        }
        .font(.system(size: 9, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func resourceIndicator(_ metrics: JupyterKernelMetrics) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .medium))

            VStack(alignment: .leading, spacing: 0) {
                if metrics.memoryFootprintBytes > 0 {
                    Text("RAM \(formatMemory(metrics.memoryFootprintBytes))")
                }

                let usages = usageLabels(metrics)
                if !usages.isEmpty {
                    Text(usages.joined(separator: " · "))
                }
            }
        }
        .font(.system(size: 8, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func usageLabels(_ metrics: JupyterKernelMetrics) -> [String] {
        var labels: [String] = []
        let cpu = Int(metrics.cpuUsage.rounded())
        if cpu > 0 {
            labels.append("CPU \(cpu)%")
        }
        if let gpuUsage = metrics.gpuUsage {
            let gpu = Int(gpuUsage.rounded())
            if gpu > 0 {
                labels.append("GPU \(gpu)%")
            }
        }
        return labels
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let gibibyte = 1_073_741_824.0
        let mebibyte = 1_048_576.0
        if Double(bytes) >= gibibyte {
            return String(format: "%.2fG", Double(bytes) / gibibyte)
        }
        return String(format: "%.1fM", max(Double(bytes) / mebibyte, 0.1))
    }

    private func shortExecutionStatus(_ execution: JupyterExecutionSnapshot) -> String {
        switch execution.phase {
        case .running: "busy"
        case .failed: "error"
        case .completed: "complete"
        }
    }

    private var statusColor: Color {
        if monitor.currentExecution != nil {
            switch monitor.currentExecution?.phase {
            case .running: .orange
            case .failed: .red
            case .completed: .green
            case nil: .gray
            }
        } else {
            switch monitor.connectionState {
            case .connected: .green
            case .searching: .orange
            case .authenticationRequired, .unavailable: .red
            case .noServer, .noSession: .gray
            }
        }
    }

    private var statusLabel: String {
        if monitor.busyKernelCount > 0 {
            return monitor.busyKernelCount == 1 ? "kernel busy" : "\(monitor.busyKernelCount) busy"
        }

        return switch monitor.connectionState {
        case .connected:
            "kernel idle"
        case .searching:
            "searching"
        case .noServer, .noSession:
            "waiting"
        case .authenticationRequired, .unavailable:
            "error"
        }
    }

    private var connectionIcon: String {
        switch monitor.connectionState {
        case .connected: "checkmark.circle"
        case .searching: "magnifyingglass"
        case .noSession: "moon.zzz"
        case .noServer: "network.slash"
        case .authenticationRequired: "lock.trianglebadge.exclamationmark"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var connectionTitle: String {
        switch monitor.connectionState {
        case .connected(let count):
            count == 1 ? "Jupyter session active" : "\(count) Jupyter sessions active"
        case .searching:
            "Looking for Jupyter…"
        case .noSession:
            "No active notebook"
        case .noServer:
            "Jupyter is not running"
        case .authenticationRequired:
            "Authentication required"
        case .unavailable:
            "Jupyter server unavailable"
        }
    }

    private var connectionSubtitle: String {
        switch monitor.connectionState {
        case .connected:
            "Waiting for the next cell."
        case .searching:
            "Checking local sessions."
        case .noSession:
            "Open a notebook and start its kernel."
        case .noServer:
            "Start Jupyter Notebook or JupyterLab."
        case .authenticationRequired:
            "The server requires a password and no token is available."
        case .unavailable(let message):
            message
        }
    }

    private func notebookName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "Notebook" : name
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CompactProgressBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                Capsule()
                    .fill(.orange)
                    .frame(width: fillWidth(available: proxy.size.width))
            }
            .frame(width: proxy.size.width, height: 4)
            .clipped()
        }
        .frame(height: 4)
        .clipped()
    }

    private func fillWidth(available: CGFloat) -> CGFloat {
        guard let value else { return min(max(available * 0.28, 12), available) }
        return available * min(max(value, 0), 1)
    }
}
