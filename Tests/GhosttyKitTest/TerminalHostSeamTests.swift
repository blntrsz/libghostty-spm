import Foundation
import GhosttyKit
@testable import GhosttyTerminal
import Testing

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
#endif

@Suite("TerminalHostSeams")
struct TerminalHostSeamTests {
    @Test
    @MainActor
    func `platform view factory defaults to the base class`() {
        let state = TerminalViewState()
        #expect(state.makePlatformView == nil)
    }

    @Test
    func `open URL kind preserves OSC 8 origin`() {
        let kind = TerminalOpenURLKind(GHOSTTY_ACTION_OPEN_URL_KIND_OSC8)
        if case .osc8 = kind {
            // Expected.
        } else {
            Issue.record("OSC 8 URL origin was erased")
        }
    }

    @Test
    @MainActor
    func `hovered link is published and cleared`() async {
        let state = TerminalViewState()

        state.terminalDidUpdateHoverLink("https://example.com/very/long/path")
        await nextMainQueueTurn()
        #expect(state.hoveredLink == "https://example.com/very/long/path")

        state.terminalDidUpdateHoverLink(nil)
        await nextMainQueueTurn()
        #expect(state.hoveredLink == nil)
    }

    @Test
    @MainActor
    func `a change reverted within one turn publishes the reverted value`() async {
        let state = TerminalViewState()
        state.terminalDidChangeTitle("~")
        await nextMainQueueTurn()
        #expect(state.title == "~")
        #expect(!state.isFocused)

        state.terminalDidChangeTitle("ls")
        state.terminalDidChangeTitle("~")
        state.terminalDidChangeFocus(true)
        state.terminalDidChangeFocus(false)
        await nextMainQueueTurn()

        #expect(state.title == "~")
        #expect(!state.isFocused)
    }

    #if !canImport(UIKit) && canImport(AppKit)
        @Test
        @MainActor
        func `snapshot renders an offscreen view`() {
            let view = AppTerminalView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
            #expect(view.snapshotImage() != nil)
        }

        @Test
        @MainActor
        func `snapshot of a zero-size view is nil`() {
            let view = AppTerminalView(frame: .zero)
            #expect(view.snapshotImage() == nil)
        }
    #endif
}

/// Resumes once every block the main queue held when this was called has
/// run — the queue is FIFO, so a deferred publish lands before this does.
private func nextMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
