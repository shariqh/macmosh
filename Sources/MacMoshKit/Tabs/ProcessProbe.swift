import Foundation

/// The two system calls that say whether a tab record's process is still the one that wrote it
/// (menu design 8.2). Tests use a stand-in.
public protocol ProcessProbe: Sendable {
    /// Whether a process with this number exists and may be signalled: `kill(pid, 0)` succeeds.
    func exists(_ pid: Int32) -> Bool
    /// When the process started, in microseconds since 1970, or nil when it can't be read.
    func startTime(of pid: Int32) -> Int64?
}

/// The real calls.
public struct SystemProcessProbe: ProcessProbe {
    public init() {}

    /// kill(2), this Mac's manual: "A value of 0, however, will cause error checking to be performed (with no
    /// signal being sent). This can be used to check the validity of pid." A number below 1 names a process
    /// group there, never one process, so it is never taken to exist.
    public func exists(_ pid: Int32) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    /// The `kern.proc.pid.<pid>` entry of sysctl(3). The SDK's `sys/sysctl.h` documents `KERN_PROC` as
    /// "struct: process entries" and `KERN_PROC_PID` as "by process id", returning `struct kinfo_proc`;
    /// `sys/proc.h` documents its `kp_proc.p_un.__p_starttime` as "process start time" (a `struct timeval`).
    /// A process that doesn't exist gives back no entry, so the length read is 0.
    public func startTime(of pid: Int32) -> Int64? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.stride else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
    }

    /// The start time of the running program, for its own record.
    public func ownStartTime() -> Int64? { startTime(of: getpid()) }
}
