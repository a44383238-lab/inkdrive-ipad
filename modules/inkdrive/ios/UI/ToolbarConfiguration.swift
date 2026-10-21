import Foundation

struct ToolbarEntry: Codable, Identifiable {
    var id = UUID()
    var tool: EditorTool
    var settings: ToolSettings
}

/// Identity belongs to each pen, not its tool type: two red pens can coexist too.
struct ToolbarConfiguration: Codable {
    var entries: [ToolbarEntry]
    var selected: UUID
    init(entries: [ToolbarEntry]) {
        let safe = entries.isEmpty ? [ToolbarEntry(tool: .pen, settings: ToolSettings())] : entries
        self.entries = safe; selected = safe[0].id
    }
    var active: ToolbarEntry { entries.first { $0.id == selected } ?? entries[0] }
    mutating func add(_ tool: EditorTool, settings: ToolSettings) {
        let entry = ToolbarEntry(tool: tool, settings: settings)
        entries.append(entry); selected = entry.id
    }
    mutating func remove(_ id: UUID) {
        guard entries.count > 1 else { return }
        entries.removeAll { $0.id == id }
        if !entries.contains(where: { $0.id == selected }) { selected = entries[0].id }
    }
    mutating func move(_ id: UUID, to destination: Int) {
        guard let old = entries.firstIndex(where: { $0.id == id }) else { return }
        let value = entries.remove(at: old)
        entries.insert(value, at: min(max(0, destination), entries.count))
    }
}
