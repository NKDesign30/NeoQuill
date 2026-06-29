import Foundation

enum WorkspaceKind: String, Codable, CaseIterable, Hashable {
    case project
    case team
    case organization

    var label: String {
        switch self {
        case .project:
            return "Projekt"
        case .team:
            return "Team"
        case .organization:
            return "Organisation"
        }
    }
}

struct MeetingWorkspace: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var kind: WorkspaceKind
    var context: String
    var colorHex: UInt32
    var archived: Bool
    var createdAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: WorkspaceKind,
        context: String = "",
        colorHex: UInt32 = 0x2EAB73,
        archived: Bool = false,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.context = context
        self.colorHex = colorHex
        self.archived = archived
        self.createdAt = createdAt
    }
}

enum WorkspaceSelection: Equatable, Hashable {
    case all
    case unassigned
    case workspace(String)

    var recordingWorkspaceId: String? {
        switch self {
        case .all, .unassigned:
            return nil
        case .workspace(let id):
            return id
        }
    }

    func includes(_ meeting: MeetingSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .unassigned:
            return meeting.workspaceId == nil
        case .workspace(let id):
            return meeting.workspaceId == id
        }
    }
}
