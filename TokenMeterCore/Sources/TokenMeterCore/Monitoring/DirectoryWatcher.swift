import Foundation

/// Watches a directory tree with FSEvents and coalesces bursts.
///
/// A live JSONL gets many writes per second; without debouncing we would re-parse
/// on every one of them. Callers get at most one callback per `debounce` interval.
public final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "com.tokenmeter.watcher")
    private var pendingWork: DispatchWorkItem?
    private let onChange: @Sendable () -> Void

    public init(paths: [String], debounce: TimeInterval = 2.0, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        queue.sync {
            guard stream == nil, !paths.isEmpty else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleCallback()
            }

            guard let s = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                debounce,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            ) else { return }

            FSEventStreamSetDispatchQueue(s, queue)
            FSEventStreamStart(s)
            stream = s
        }
    }

    public func stop() {
        queue.sync {
            pendingWork?.cancel()
            pendingWork = nil
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func scheduleCallback() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
