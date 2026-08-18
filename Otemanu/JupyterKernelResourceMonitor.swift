import Darwin
import Foundation

struct JupyterKernelMetrics: Equatable, Sendable {
    let kernelID: String
    let processID: pid_t
    let memoryFootprintBytes: UInt64
    let cpuUsage: Double
    let gpuUsage: Double?
}

actor JupyterKernelResourceMonitor {
    private struct CumulativeSample {
        let cpuNanoseconds: UInt64
        let gpuNanoseconds: UInt64?
        let date: Date
    }

    private struct ProcessIdentity {
        let processID: pid_t
    }

    private var processesByKernel: [String: ProcessIdentity] = [:]
    private var previousSamples: [pid_t: CumulativeSample] = [:]

    func discard(kernelID: String) {
        guard let process = processesByKernel.removeValue(forKey: kernelID) else { return }
        previousSamples.removeValue(forKey: process.processID)
    }

    func discardAll() {
        processesByKernel.removeAll()
        previousSamples.removeAll()
    }

    func sample(kernelIDs: Set<String>) -> [String: JupyterKernelMetrics] {
        processesByKernel = processesByKernel.filter { kernelIDs.contains($0.key) }

        let unresolved = kernelIDs.filter { kernelID in
            guard let process = processesByKernel[kernelID] else { return true }
            return processTaskInfo(processID: process.processID) == nil
        }

        if !unresolved.isEmpty {
            discoverProcesses(for: Set(unresolved))
        }

        let now = Date()
        var metrics: [String: JupyterKernelMetrics] = [:]
        var activeProcessIDs = Set<pid_t>()

        for kernelID in kernelIDs {
            guard
                let process = processesByKernel[kernelID],
                processTaskInfo(processID: process.processID) != nil
            else {
                continue
            }

            // Notebook code can execute in subprocesses (for example joblib,
            // multiprocessing or native libraries). Aggregate the complete live
            // process tree so the indicator follows the resources used by the
            // kernel workload rather than only the Python parent process.
            let processIDs = processTreeProcessIDs(rootProcessID: process.processID)
            let taskInfos = processIDs.compactMap(processTaskInfo(processID:))
            let cpuNanoseconds = taskInfos.reduce(UInt64(0)) {
                $0 + $1.pti_total_user + $1.pti_total_system
            }
            let memoryFootprintBytes = processIDs.reduce(UInt64(0)) {
                $0 + processMemoryFootprint(processID: $1)
            }
            let gpuSamples = processIDs.compactMap(processGPUTime(processID:))
            let gpuNanoseconds =
                gpuSamples.isEmpty
                ? nil
                : gpuSamples.reduce(UInt64(0), +)
            let current = CumulativeSample(
                cpuNanoseconds: cpuNanoseconds,
                gpuNanoseconds: gpuNanoseconds,
                date: now
            )

            let previous = previousSamples[process.processID]
            let elapsed = previous.map { now.timeIntervalSince($0.date) } ?? 0
            let cpuUsage = usagePercentage(
                current: cpuNanoseconds,
                previous: previous?.cpuNanoseconds,
                elapsed: elapsed,
                maximum: nil
            )
            let gpuUsage = gpuNanoseconds.map { currentGPU in
                usagePercentage(
                    current: currentGPU,
                    previous: previous?.gpuNanoseconds,
                    elapsed: elapsed,
                    maximum: 100
                )
            }

            metrics[kernelID] = JupyterKernelMetrics(
                kernelID: kernelID,
                processID: process.processID,
                memoryFootprintBytes: memoryFootprintBytes,
                cpuUsage: cpuUsage,
                gpuUsage: gpuUsage
            )
            previousSamples[process.processID] = current
            activeProcessIDs.insert(process.processID)
        }

        previousSamples = previousSamples.filter { activeProcessIDs.contains($0.key) }
        return metrics
    }

    private func discoverProcesses(for kernelIDs: Set<String>) {
        guard !kernelIDs.isEmpty else { return }

        for processID in allProcessIDs() {
            guard let process = processArguments(processID: processID) else { continue }
            let searchableArguments = process.arguments.joined(separator: "\u{0}")

            for kernelID in kernelIDs where searchableArguments.contains(kernelID) {
                processesByKernel[kernelID] = ProcessIdentity(
                    processID: processID
                )
            }
        }
    }

    private func allProcessIDs() -> [pid_t] {
        var processIDs = [pid_t](repeating: 0, count: 8192)
        let count = processIDs.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(processIDs.prefix(Int(count))).filter { $0 > 0 }
    }

    private func processArguments(processID: pid_t) -> (
        executablePath: String,
        arguments: [String]
    )? {
        var query = [CTL_KERN, KERN_PROCARGS2, processID]
        var size = 0
        guard sysctl(&query, u_int(query.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&query, u_int(query.count), &bytes, &size, nil, 0) == 0 else {
            return nil
        }

        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argumentCount = bytes.withUnsafeBytes {
            Int($0.loadUnaligned(as: Int32.self))
        }
        guard argumentCount > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        let reportedExecutable = readCString(in: bytes, index: &index)
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while index < bytes.count, arguments.count < argumentCount {
            if let argument = readCString(in: bytes, index: &index), !argument.isEmpty {
                arguments.append(argument)
            } else {
                index += 1
            }
        }

        let argumentExecutable = arguments.first.flatMap { $0.hasPrefix("/") ? $0 : nil }
        let executable =
            argumentExecutable
            ?? reportedExecutable
            ?? processPath(processID: processID)

        guard let executable else { return nil }
        return (executable, arguments)
    }

    private func readCString(in bytes: [UInt8], index: inout Int) -> String? {
        guard index < bytes.count else { return nil }
        let start = index
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        let value = String(decoding: bytes[start..<index], as: UTF8.self)
        if index < bytes.count { index += 1 }
        return value
    }

    private func processPath(processID: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBytes { bytes in
            proc_pidpath(processID, bytes.baseAddress, UInt32(bytes.count))
        }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private func processTaskInfo(processID: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(
                processID,
                PROC_PIDTASKINFO,
                0,
                pointer,
                expectedSize
            )
        }
        return result == expectedSize ? info : nil
    }

    private func processMemoryFootprint(processID: pid_t) -> UInt64 {
        var usage = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(
                processID,
                RUSAGE_INFO_V0,
                UnsafeMutableRawPointer(pointer)
                    .assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard result == 0 else {
            return processTaskInfo(processID: processID)?.pti_resident_size ?? 0
        }
        return usage.ri_phys_footprint > 0
            ? usage.ri_phys_footprint
            : usage.ri_resident_size
    }

    private func processTreeProcessIDs(rootProcessID: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var pending = [rootProcessID]
        var visited = Set<pid_t>()

        while let processID = pending.popLast() {
            guard visited.insert(processID).inserted else { continue }
            guard processTaskInfo(processID: processID) != nil else { continue }
            result.append(processID)
            pending.append(contentsOf: childProcessIDs(parentProcessID: processID))
        }

        return result
    }

    private func childProcessIDs(parentProcessID: pid_t) -> [pid_t] {
        var processIDs = [pid_t](repeating: 0, count: 512)
        let count = processIDs.withUnsafeMutableBytes { buffer in
            proc_listchildpids(parentProcessID, buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(processIDs.prefix(Int(count))).filter { $0 > 0 }
    }

    private func processGPUTime(processID: pid_t) -> UInt64? {
        var taskPort: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, processID, &taskPort) == KERN_SUCCESS else {
            return nil
        }
        defer { mach_port_deallocate(mach_task_self_, taskPort) }

        var info = task_power_info_v2_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_power_info_v2_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(taskPort, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.gpu_energy.task_gpu_utilisation
    }

    private func usagePercentage(
        current: UInt64,
        previous: UInt64?,
        elapsed: TimeInterval,
        maximum: Double?
    ) -> Double {
        guard let previous, current >= previous, elapsed > 0 else { return 0 }
        let percentage = Double(current - previous) / (elapsed * 1_000_000_000) * 100
        return min(max(percentage, 0), maximum ?? percentage)
    }

}
