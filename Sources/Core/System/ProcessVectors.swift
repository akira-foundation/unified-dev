import Darwin

public struct ProcessVector: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let pid: Int32
    public let strings: [String]?
    public let paths: [String]

    public init(pid: Int32, strings: [String]?, paths: [String] = []) {
        self.pid = pid
        self.strings = strings
        self.paths = paths
    }

    public var description: String { "process \(pid)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["pid": pid]) }
}

public enum ProcessVectors {
    enum Reading: Equatable {
        case strings([String])
        case gone
        case unreadable
    }

    private static let rereads = 10
    private static let rereadPause: useconds_t = 30_000

    public static func ofOtherProcesses() -> [ProcessVector]? {
        ofThisUser()?.filter { $0.pid != getpid() }
    }

    public static func ofThisUser() -> [ProcessVector]? {
        guard let processes = processesOfThisUser(), let capacity = argumentCapacity() else { return nil }
        var buffer = [UInt8](repeating: 0, count: capacity)
        return settle(
            pids: processes.filter { $0.kp_proc.p_stat != SZOMB }.map(\.kp_proc.p_pid),
            read: { read($0, into: &buffer) },
            isZombie: isZombie,
            pause: { usleep(rereadPause) }
        ).map { ProcessVector(pid: $0.pid, strings: $0.strings, paths: ProcessPaths.of($0.pid)) }
    }

    static func settle(
        pids: [Int32],
        rereads: Int = Self.rereads,
        read: (Int32) -> Reading,
        isZombie: (Int32) -> Bool,
        pause: () -> Void
    ) -> [ProcessVector] {
        var readings = pids.map { (pid: $0, reading: read($0)) }
        for _ in 0..<rereads where readings.contains(where: { $0.reading == .unreadable }) {
            pause()
            readings = readings.map { entry in
                guard entry.reading == .unreadable else { return entry }
                return (entry.pid, isZombie(entry.pid) ? .gone : read(entry.pid))
            }
        }
        return readings.compactMap { entry in
            switch entry.reading {
            case .strings(let strings): ProcessVector(pid: entry.pid, strings: strings)
            case .unreadable: ProcessVector(pid: entry.pid, strings: nil)
            case .gone: nil
            }
        }
    }

    private static func read(_ pid: Int32, into buffer: inout [UInt8]) -> Reading {
        var name = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0 else {
            return errno == ESRCH ? .gone : .unreadable
        }
        return .strings(strings(inArguments: buffer.prefix(size)))
    }

    static func isZombie(_ pid: Int32) -> Bool {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&name, 4, &process, &size, nil, 0) == 0 else { return false }
        return size == 0 || process.kp_proc.p_stat == SZOMB
    }

    static func strings(inArguments bytes: ArraySlice<UInt8>) -> [String] {
        bytes.dropFirst(MemoryLayout<Int32>.size)
            .split(separator: 0)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func processesOfThisUser() -> [kinfo_proc]? {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0 else { return nil }
        let room = size / MemoryLayout<kinfo_proc>.stride + 64
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: room)
        size = room * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&name, 4, &processes, &size, nil, 0) == 0 else { return nil }
        return Array(processes.prefix(size / MemoryLayout<kinfo_proc>.stride))
    }

    private static func argumentCapacity() -> Int? {
        var capacity = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname("kern.argmax", &capacity, &size, nil, 0) == 0, capacity > 0 else { return nil }
        return capacity
    }
}
