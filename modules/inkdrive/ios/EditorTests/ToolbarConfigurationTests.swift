import XCTest
@testable import InkDriveCore

final class ToolbarConfigurationTests: XCTestCase {
    func testSameToolCanBeAddedRepeatedlyWithIndependentSettings() throws {
        var black = ToolSettings(); black.color = "#000000"
        var red = ToolSettings(); red.color = "#E60012"; red.width = 1.5
        var bar = ToolbarConfiguration(entries: [ToolbarEntry(tool: .pen, settings: black)])
        bar.add(.pen, settings: red); bar.add(.pen, settings: red)
        XCTAssertEqual(bar.entries.count, 3)
        XCTAssertEqual(Set(bar.entries.map(\.id)).count, 3)
        bar.entries[1].settings.width = 7
        XCTAssertEqual(bar.entries[0].settings.width, black.width)
        XCTAssertEqual(bar.entries[2].settings.width, 1.5)
        let restored = try JSONDecoder().decode(ToolbarConfiguration.self, from: JSONEncoder().encode(bar))
        XCTAssertEqual(restored.entries.map(\.id), bar.entries.map(\.id))
        XCTAssertEqual(restored.selected, bar.selected)
    }
    func testReorderAndRemovalPreserveSelectedPenIdentity() throws {
        var bar = ToolbarConfiguration(entries: [ToolbarEntry(tool: .pen, settings: ToolSettings())])
        bar.add(.pen, settings: ToolSettings()); let selected = bar.selected
        bar.add(.marker, settings: ToolSettings()); bar.selected = selected
        bar.move(selected, to: 0)
        XCTAssertEqual(bar.entries[0].id, selected)
        XCTAssertEqual(bar.selected, selected)
        bar.remove(bar.entries[1].id)
        XCTAssertEqual(bar.selected, selected)
        bar.remove(selected)
        XCTAssertNotEqual(bar.selected, selected)
        bar.remove(bar.selected)
        XCTAssertEqual(bar.entries.count, 1)
    }
}
