import Foundation
import Darwin

/// A process-held file lock. Leave the inode in place; removing it would permit
/// another process to lock a replacement file while the first lock is held.
public final class InstanceLock {
    private var descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { release() }

    public static func acquire(at url: URL) throws -> InstanceLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return InstanceLock(descriptor)
    }

    public func release() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
    }
}
