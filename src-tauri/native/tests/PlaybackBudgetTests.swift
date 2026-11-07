// Compile with PlaybackBudget.swift; intentionally imports no audio APIs and plays nothing.
@main
struct PlaybackBudgetTests {
    static func main() {
        // Regression: the old 48k cap silently rejected 3/5 seconds of burst output.
        var legacy = 0
        for _ in 0..<5 { if legacy + 24_000 <= 48_000 { legacy += 24_000 } }
        assert(legacy == 48_000)
        var budget = PlaybackBudget()
        var tickets: [PlaybackBudget.Ticket] = []
        for _ in 0..<5 { tickets.append(budget.admit(24_000)!) }
        assert(budget.frames == 120_000)
        for ticket in tickets.reversed() { budget.complete(ticket) }
        assert(budget.frames == 0)
        // Single chunks >2s and an exact 30s burst are both admitted immediately.
        let large = budget.admit(72_000)!
        assert(budget.frames == 72_000)
        budget.complete(large); budget.complete(large)
        assert(budget.frames == 0, "Duplicate completion must not release another buffer")
        let full = budget.admit(PlaybackBudget.maxFrames)!
        assert(budget.admit(1) == nil)
        assert(budget.frames == PlaybackBudget.maxFrames)
        budget.complete(full)
        assert(budget.admit(PlaybackBudget.maxFrames + 1) == nil)
        assert(budget.admit(Int.max) == nil)
        assert(budget.admit(0) == nil && budget.admit(-1) == nil)
        // Clear/interrupt must invalidate old completions, including after new admission.
        let stale = budget.admit(72_000)!
        budget.clear()
        let fresh = budget.admit(24_000)!
        budget.complete(stale)
        assert(budget.frames == 24_000)
        budget.complete(fresh)
        assert(budget.frames == 0)
        // Bound object overhead even when PCM fragments contain just one sample.
        for _ in 0..<PlaybackBudget.maxBuffers { assert(budget.admit(1) != nil) }
        assert(budget.admit(1) == nil)
        budget.fail()
        assert(budget.frames == 0 && budget.failed)
        assert(budget.admit(24_000) == nil, "Failure must latch against in-flight audio")
        budget.complete(stale)
        assert(budget.frames == 0)
        budget.clear()
        assert(!budget.failed && budget.admit(24_000) != nil)
        print("PlaybackBudget: burst, large/split chunks, bounds, completion, clear and failure checks passed (no audio devices used)")
    }
}
