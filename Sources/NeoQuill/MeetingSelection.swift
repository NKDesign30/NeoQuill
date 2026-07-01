import Foundation

/// Die Selection-State-Machine der Meeting-Liste als reiner Value-Type:
/// Primär-Selektion, Multi-Select-Menge und der daraus folgende View-Modus.
///
/// Vorher lebte diese Anchor-/Range-/Filter-Reduktion als Methoden-Trio im
/// AppState — hinter einem Konstruktor, der den kompletten Service-Graph
/// (SQLite, Audio-Engine, Keychain, MenuBar) bootet, und damit faktisch
/// untestbar. Hier ist das Interface die Test-Oberfläche; AppState published
/// nur noch und reicht die sichtbare Meeting-Reihenfolge herein.
struct MeetingSelection: Equatable {

    /// Das aktive Meeting (Detail-View) — Anchor für Range-Selektion.
    private(set) var primaryId: String?
    /// Die Multi-Select-Menge. Enthält `primaryId`, sobald selektiert wurde.
    private(set) var ids: Set<String> = []
    private(set) var viewMode: ViewMode = .empty

    /// Einzel-Selektion: genau dieses Meeting, Detail-Modus.
    mutating func select(_ meetingId: String) {
        primaryId = meetingId
        ids = [meetingId]
        viewMode = .detail
    }

    mutating func showEmpty() {
        viewMode = .empty
        primaryId = nil
    }

    /// Gleicht die Selektion mit der aktuell sichtbaren (gefilterten) Liste ab:
    /// unsichtbare IDs fliegen raus, eine verwaiste Primär-Selektion springt
    /// auf das erste sichtbare Meeting, eine leere Liste erzwingt Empty-Modus.
    mutating func sync(visible: [String]) {
        let visibleIds = Set(visible)
        let filtered = ids.intersection(visibleIds)
        if filtered != ids {
            ids = filtered
        }
        if visible.isEmpty {
            primaryId = nil
            ids = []
            if viewMode == .detail { viewMode = .empty }
        } else if primaryId == nil || !visibleIds.contains(primaryId!) {
            primaryId = visible.first
            ids = primaryId.map { [$0] } ?? []
            if viewMode == .empty { viewMode = .detail }
        } else if ids.isEmpty, let primaryId {
            ids = [primaryId]
        }
    }

    /// Cmd-Klick: Meeting zur Menge hinzufügen/entfernen. Fällt die Menge
    /// dabei leer, wird das geklickte Meeting zur Einzel-Selektion. Wird die
    /// Primär-Selektion entfernt, rückt das erste sichtbare Meeting der
    /// Restmenge nach.
    mutating func toggle(_ meetingId: String, visible: [String]) {
        var selection = ids
        if selection.isEmpty, let primaryId {
            selection.insert(primaryId)
        }
        let wasSelected = selection.contains(meetingId)
        if wasSelected {
            selection.remove(meetingId)
        } else {
            selection.insert(meetingId)
        }
        guard !selection.isEmpty else {
            select(meetingId)
            return
        }
        ids = selection
        if wasSelected, primaryId == meetingId {
            primaryId = visible.first(where: { selection.contains($0) })
        } else {
            primaryId = meetingId
        }
        viewMode = .detail
    }

    /// Shift-Klick: Range vom Anchor (Primär-Selektion) bis zum Ziel — in
    /// sichtbarer Reihenfolge, richtungsunabhängig. Ohne Anchor: Einzel-Selektion.
    mutating func extend(to meetingId: String, visible: [String]) {
        guard let targetIndex = visible.firstIndex(of: meetingId),
              let anchorId = primaryId,
              let anchorIndex = visible.firstIndex(of: anchorId) else {
            select(meetingId)
            return
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        ids = Set(visible[lower...upper])
        primaryId = meetingId
        viewMode = .detail
    }

    /// Kontextmenü-Ziel: die Mehrfach-Selektion, wenn der Anchor Teil davon
    /// ist — sonst nur das angeklickte Meeting.
    func contextIds(anchor meetingId: String) -> Set<String> {
        ids.contains(meetingId) ? ids : [meetingId]
    }
}
