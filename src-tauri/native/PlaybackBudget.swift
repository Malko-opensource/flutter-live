// Main-thread-only admission bookkeeping; no devices or audio APIs.
// Live output arrives faster than realtime. Schedule immediately (no prebuffer),
// retaining at most 30s of mono 24kHz Float32 PCM (~2.88MB), plus bounded metadata.
// This permits bursty sentences, but a slow consumer can still exhaust the budget.
struct PlaybackBudget {
    static let maxFrames = 24_000 * 30
    static let maxBuffers = 4096
    struct Ticket { let epoch: UInt64; let id: UInt64 }
    private(set) var frames = 0
    private(set) var failed = false
    private var epoch: UInt64 = 0
    private var nextID: UInt64 = 0
    private var pending: [UInt64: Int] = [:]

    mutating func admit(_ count: Int) -> Ticket? {
        guard !failed, count > 0, count <= Self.maxFrames - frames,
              pending.count < Self.maxBuffers else { return nil }
        let ticket = Ticket(epoch: epoch, id: nextID)
        nextID &+= 1
        pending[ticket.id] = count
        frames += count
        return ticket
    }
    mutating func complete(_ ticket: Ticket) {
        guard ticket.epoch == epoch, let count = pending.removeValue(forKey: ticket.id) else { return }
        frames -= count
    }
    mutating func clear() {
        epoch &+= 1
        frames = 0
        pending.removeAll(keepingCapacity: false)
        failed = false
    }
    mutating func fail() {
        clear()
        // Ignore already-in-flight play commands until explicitly cleared/re-enabled.
        failed = true
    }
}
