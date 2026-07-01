import XCTest
@testable import NeoQuill

/// Erste direkte Tests für die Meeting-Selection-Reduktion — vorher lebte sie
/// untestbar hinter dem AppState-Konstruktor (der SQLite, Audio-Engine,
/// Keychain und MenuBar bootet).
final class MeetingSelectionTests: XCTestCase {

    private let visible = ["m1", "m2", "m3", "m4"]

    // MARK: - select / showEmpty

    func testSelectSetsPrimaryIdsAndDetailMode() {
        var selection = MeetingSelection()
        selection.select("m2")
        XCTAssertEqual(selection.primaryId, "m2")
        XCTAssertEqual(selection.ids, ["m2"])
        XCTAssertEqual(selection.viewMode, .detail)
    }

    func testShowEmptyClearsPrimaryButKeepsIds() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.showEmpty()
        XCTAssertNil(selection.primaryId)
        XCTAssertEqual(selection.viewMode, .empty)
    }

    // MARK: - sync (Workspace-Filter-Abgleich)

    func testSyncWithEmptyListClearsEverything() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.sync(visible: [])
        XCTAssertNil(selection.primaryId)
        XCTAssertTrue(selection.ids.isEmpty)
        XCTAssertEqual(selection.viewMode, .empty)
    }

    func testSyncDropsFilteredIdsAndKeepsValidPrimary() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.toggle("m3", visible: visible)
        selection.sync(visible: ["m1", "m2"])
        XCTAssertEqual(selection.primaryId, "m1")
        XCTAssertEqual(selection.ids, ["m1"], "Gefiltertes m3 muss aus der Menge fallen")
    }

    func testSyncMovesOrphanedPrimaryToFirstVisible() {
        var selection = MeetingSelection()
        selection.select("m4")
        selection.sync(visible: ["m1", "m2"])
        XCTAssertEqual(selection.primaryId, "m1")
        XCTAssertEqual(selection.ids, ["m1"])
        XCTAssertEqual(selection.viewMode, .detail)
    }

    func testSyncPromotesEmptyToDetailWhenMeetingsAppear() {
        var selection = MeetingSelection()
        selection.sync(visible: visible)
        XCTAssertEqual(selection.primaryId, "m1")
        XCTAssertEqual(selection.viewMode, .detail)
    }

    func testSyncRestoresIdsFromPrimaryWhenSetIsEmpty() {
        var selection = MeetingSelection()
        selection.select("m2")
        selection.sync(visible: ["m3"])       // m2 fällt raus → springt auf m3
        selection.sync(visible: ["m3", "m2"]) // m3 bleibt gültig
        XCTAssertEqual(selection.primaryId, "m3")
        XCTAssertEqual(selection.ids, ["m3"])
    }

    // MARK: - toggle (Cmd-Klick)

    func testToggleAddsSecondMeeting() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.toggle("m3", visible: visible)
        XCTAssertEqual(selection.ids, ["m1", "m3"])
        XCTAssertEqual(selection.primaryId, "m3")
        XCTAssertEqual(selection.viewMode, .detail)
    }

    func testToggleRemovingPrimaryPromotesFirstVisibleInSelection() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.toggle("m3", visible: visible)
        selection.toggle("m2", visible: visible)
        selection.toggle("m2", visible: visible) // m2 (primär) wieder entfernen
        XCTAssertEqual(selection.ids, ["m1", "m3"])
        XCTAssertEqual(selection.primaryId, "m1", "Erstes sichtbares Meeting der Restmenge rückt nach")
    }

    func testToggleRemovingLastMeetingFallsBackToSingleSelect() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.toggle("m1", visible: visible)
        XCTAssertEqual(selection.ids, ["m1"], "Leere Menge fällt auf Einzel-Selektion des Geklickten zurück")
        XCTAssertEqual(selection.primaryId, "m1")
    }

    func testToggleSeedsSetFromPrimaryWhenSetIsEmpty() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.showEmpty()   // primary nil, ids behalten "m1"
        selection.select("m2")  // frische Einzel-Selektion
        selection.toggle("m4", visible: visible)
        XCTAssertEqual(selection.ids, ["m2", "m4"])
    }

    // MARK: - extend (Shift-Klick)

    func testExtendSelectsRangeFromAnchor() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.extend(to: "m3", visible: visible)
        XCTAssertEqual(selection.ids, ["m1", "m2", "m3"])
        XCTAssertEqual(selection.primaryId, "m3")
    }

    func testExtendWorksBackwards() {
        var selection = MeetingSelection()
        selection.select("m4")
        selection.extend(to: "m2", visible: visible)
        XCTAssertEqual(selection.ids, ["m2", "m3", "m4"])
        XCTAssertEqual(selection.primaryId, "m2")
    }

    func testExtendWithoutAnchorFallsBackToSingleSelect() {
        var selection = MeetingSelection()
        selection.extend(to: "m2", visible: visible)
        XCTAssertEqual(selection.ids, ["m2"])
        XCTAssertEqual(selection.primaryId, "m2")
    }

    // MARK: - contextIds

    func testContextIdsReturnsSelectionWhenAnchorIsPart() {
        var selection = MeetingSelection()
        selection.select("m1")
        selection.toggle("m2", visible: visible)
        XCTAssertEqual(selection.contextIds(anchor: "m1"), ["m1", "m2"])
    }

    func testContextIdsReturnsSingletonWhenAnchorOutsideSelection() {
        var selection = MeetingSelection()
        selection.select("m1")
        XCTAssertEqual(selection.contextIds(anchor: "m4"), ["m4"])
    }
}
