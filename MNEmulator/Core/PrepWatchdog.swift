import Foundation

final class PrepWatchdog {
    static let shared = PrepWatchdog()

    private let lock = NSLock()
    private var stage = "idle"
    private var timer: DispatchSourceTimer?
    private var reportCount = 0
    private var maxReports = 30

    func setStage(_ s: String) {
        lock.lock()
        stage = s
        lock.unlock()
    }

    func currentStage() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stage
    }

    func start(interval: TimeInterval = 3, maxReports: Int = 30) {
        stop()
        self.maxReports = maxReports
        let q = DispatchQueue.global(qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.reportCount += 1
            Box64Bridge.writeDiag("watchdog: still_preparing stage=\(self.currentStage()) report=\(self.reportCount)")
            if self.reportCount >= self.maxReports {
                t.cancel()
            }
        }
        lock.lock()
        reportCount = 0
        timer = t
        lock.unlock()
        t.resume()
    }

    func stop() {
        lock.lock()
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
    }
}
