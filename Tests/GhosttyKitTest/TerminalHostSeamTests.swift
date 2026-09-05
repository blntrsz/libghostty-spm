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
    func `search callbacks expose host requests and asynchronous match state`() async {
        let state = TerminalViewState()
        let bridge = TerminalCallbackBridge(delegate: state)
        var requestedQuery: String?
        var didRequestSearch = false
        var didRequestEndSearch = false
        state.onSearchRequest = { query in
            didRequestSearch = true
            requestedQuery = query
        }
        state.onSearchEndRequest = {
            didRequestEndSearch = true
        }

        "needle".withCString { needle in
            var action = ghostty_action_s()
            action.tag = GHOSTTY_ACTION_START_SEARCH
            action.action.start_search = ghostty_action_start_search_s(needle: needle)
            bridge.handleAction(action)
        }
        #expect(didRequestSearch)
        #expect(requestedQuery == "needle")

        var totalAction = ghostty_action_s()
        totalAction.tag = GHOSTTY_ACTION_SEARCH_TOTAL
        totalAction.action.search_total = ghostty_action_search_total_s(total: 4)
        bridge.handleAction(totalAction)

        var selectedAction = ghostty_action_s()
        selectedAction.tag = GHOSTTY_ACTION_SEARCH_SELECTED
        selectedAction.action.search_selected = ghostty_action_search_selected_s(selected: 2)
        bridge.handleAction(selectedAction)
        await nextMainQueueTurn()
        #expect(state.searchMatchCount == 4)
        #expect(state.selectedSearchMatchIndex == 2)

        totalAction.action.search_total.total = -1
        selectedAction.action.search_selected.selected = -1
        bridge.handleAction(totalAction)
        bridge.handleAction(selectedAction)
        await nextMainQueueTurn()
        #expect(state.searchMatchCount == nil)
        #expect(state.selectedSearchMatchIndex == nil)

        var endAction = ghostty_action_s()
        endAction.tag = GHOSTTY_ACTION_END_SEARCH
        bridge.handleAction(endAction)
        #expect(didRequestEndSearch)
    }

    @Test
    @MainActor
    func `renderer search publishes match count and selected index`() async {
        let harness = GhosttySurfaceHarness()
        defer { harness.tearDown() }
        let state = TerminalViewState()
        harness.coordinator.delegate = state
        harness.receive("alpha needle\\r\\nbeta\\r\\ngamma needle\\r\\ndelta needle\\r\\n")

        #expect(harness.surface?.performBindingAction("search:needle") == true)
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline, state.searchMatchCount != 3 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(state.searchMatchCount == 3)

        #expect(harness.surface?.performBindingAction("navigate_search:next") == true)
        let selectionDeadline = clock.now + .seconds(2)
        while clock.now < selectionDeadline, state.selectedSearchMatchIndex == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.selectedSearchMatchIndex != nil)
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
