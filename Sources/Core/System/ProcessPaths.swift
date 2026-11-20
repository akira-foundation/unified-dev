import Darwin

enum ProcessPaths {
    static func of(_ pid: Int32) -> [String] {
        (workingDirectory(of: pid).map { [$0] } ?? []) + openFiles(of: pid)
    }

    private static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return path(in: info.pvi_cdir.vip_path)
    }

    private static func openFiles(of pid: Int32) -> [String] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let filled = descriptors.withUnsafeMutableBytes { room in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, room.baseAddress, Int32(room.count))
        }
        guard filled > 0 else { return [] }
        return descriptors.prefix(Int(filled) / stride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) }
            .compactMap { file(of: pid, descriptor: $0.proc_fd) }
    }

    private static func file(of pid: Int32, descriptor: Int32) -> String? {
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        guard proc_pidfdinfo(pid, descriptor, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
        return path(in: info.pvip.vip_path)
    }

    private static func path<Characters>(in characters: Characters) -> String? {
        let path = withUnsafeBytes(of: characters) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }
}
