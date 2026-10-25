import Foundation


/// Watches folders for changes with kernel events: no polling, no cost while
/// nothing changes. Several quick changes are reported once.
final class FolderWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func watch(_ folders: [URL]) {
        stop()
        for folder in Set(folders.map(\.standardizedFileURL)) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in self?.changed() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    deinit { stop() }
}
