import Foundation

/// Arama alanı gibi hızlı değişen girdilerde gereksiz iş yapmayı engeller.
///
/// Kullanım:
/// ```swift
/// private let searchDebouncer = Debouncer(delay: .milliseconds(300))
/// ...
/// searchDebouncer.schedule { [weak self] in await self?.performSearch(query) }
/// ```
@MainActor
final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration = .milliseconds(300)) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
