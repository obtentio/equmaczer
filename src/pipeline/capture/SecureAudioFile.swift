import Darwin
import Foundation

/// Created off the render thread. Only the owner and coreaudiod receive access.
enum SecureAudioFile {
    static func create() throws -> (descriptor: Int32, path: String) {
        var template = Array("/private/tmp/equmaczer-audio-XXXXXX".utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw SharedMemoryCaptureError.createFailed(errno) }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        do {
            guard fchmod(fd, 0o600) == 0 else { throw SharedMemoryCaptureError.createFailed(errno) }
            // File-owner ACL changes do not need administrator privileges. No shell
            // interpolation, inherited world/group access, or predictable pathname.
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+a", "user:_coreaudiod allow read,write", path]
            chmod.standardError = FileHandle.nullDevice
            try chmod.run()
            chmod.waitUntilExit()
            guard chmod.terminationStatus == 0 else { throw SharedMemoryCaptureError.createFailed(EACCES) }
            return (fd, path)
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
    }
}
