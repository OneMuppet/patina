import CoreServices
import Foundation

/// Thin FSEvents wrapper: fires `onChange` (on the main queue) whenever anything
/// in the watched folder tree is added, removed, renamed, or modified. This is
/// what makes the sidebar update live when files change on disk.
final class FolderWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var info: UnsafeMutableRawPointer?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        let infoPtr = Unmanaged.passRetained(self).toOpaque()
        info = infoPtr
        var context = FSEventStreamContext(version: 0, info: infoPtr,
                                           retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, flags)
        else {
            Unmanaged<FolderWatcher>.fromOpaque(infoPtr).release()
            info = nil
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let info {
            Unmanaged<FolderWatcher>.fromOpaque(info).release()
            self.info = nil
        }
    }

    deinit { stop() }
}
