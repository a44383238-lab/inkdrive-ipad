import XCTest
import PencilKit
import UIKit
@testable import InkDriveCore

@MainActor final class IntegrationTests: XCTestCase {
    func testIndependentJournalSurvivesRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("note.pdf"), bytes = PDFModel.blank(template: .plain)
        let journal = try InkJournal(documentURL: url, directory: root)
        try journal.write(bytes, expected: "before")
        let reopened = try InkJournal(documentURL: url, directory: root)
        XCTAssertEqual(try reopened.read()?.pdf, bytes)
        XCTAssertEqual(try reopened.read()?.expected, "before")
        try reopened.clear(); XCTAssertNil(try reopened.read())
    }
    func testVectorAppearanceAndPortableCommitKeepIdentityAndSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try PDFModel(data: PDFModel.blank(template: .plain)), url = root.appendingPathComponent("note.pdf")
        let points = [CGPoint(x: 40, y: 60), CGPoint(x: 150, y: 130)].enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i) * 0.2, size: CGSize(width: 5, height: 5), opacity: 1, force: 0.8, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 100)))])
        model.pages[0].drawing = drawing
        let file = try model.snapshot(); try file.write(to: url)
        let pdfAttachment = XCTAttachment(data: file, uniformTypeIdentifier: "com.adobe.pdf"); pdfAttachment.name = "Native vector appearance"; pdfAttachment.lifetime = .keepAlways; add(pdfAttachment)
        let reopened = try PDFModel(data: file)
        XCTAssertEqual(reopened.documentID, model.documentID); XCTAssertEqual(reopened.pages[0].id, model.pages[0].id)
        XCTAssertEqual(reopened.pages[0].drawing.strokes.count, 1)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("/Subtype /Image"))
        let store = try InkCommitStore(root: root, documentID: model.documentID, documentURL: url)
        try store.publish(reopened, fileBytes: file)
        let folder = root.appendingPathComponent(".inkdrive/documents/\(model.documentID.uuidString.lowercased())")
        let commitURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("commits"), includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: commitURL)
        XCTAssertEqual(commitURL.deletingPathExtension().lastPathComponent, CoordinatedStore.digest(bytes))
        let descriptor = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["source", "ink", "native"] {
            let ref = try XCTUnwrap(descriptor[key] as? [String: Any]), hash = try XCTUnwrap(ref["sha256"] as? String)
            let data = try Data(contentsOf: folder.appendingPathComponent("objects/\(hash)"))
            XCTAssertEqual(CoordinatedStore.digest(data), hash); XCTAssertEqual(data.count, ref["bytes"] as? Int)
            if key == "ink" {
                let ink = try JSONDecoder().decode(PortableInkDocument.self, from: data)
                XCTAssertEqual(ink.pages[0].strokes[0].id, PortableInkExporter.stableIDs(drawing, pageID: model.pages[0].id)[0].uuidString.lowercased())
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); attachment.name = "Native portable ink"; attachment.lifetime = .keepAlways; add(attachment)
            }
            if key == "source" { let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf"); attachment.name = "Native ink background"; attachment.lifetime = .keepAlways; add(attachment) }
        }
        XCTAssertEqual(try Data(contentsOf: url), file)
    }
    func testSchoolParserKeepsCourseCodesAndRejectsExternalResourceLinks() throws {
        let course = CampusCourse(id: 1, fullname: "통계", shortname: "통계 (2026-0020, IE2400211_066)")
        XCTAssertEqual(course.identity?.term, "2026-0020"); XCTAssertEqual(course.identity?.code, "IE2400211_066")
        let html = "<a class='x' href='/mod/ubfile/view.php?id=12&amp;x=2'><span>자료</span></a><a href='https://evil.test/mod/ubfile/view.php?id=13'>외부</a><a href='/mod/assign/view.php?id=14'>과제</a>"
        XCTAssertEqual(CampusHTML.resources(html).map(\.id), ["12", "14"])
        XCTAssertEqual(CampusHTML.resources(html)[0].title, "자료")
        XCTAssertFalse(CampusHTML.safeName("../../x.pdf").contains("/"))
        XCTAssertEqual(CampusHTML.text("<h1>과제</h1><script>M.cfg={sesskey:'private'}</script><style>hidden</style>"), "과제")
        XCTAssertEqual(CampusHTML.pluginFiles("<a href='https://evil.test/pluginfile.php/a.pdf'>bad</a>").count, 0)
    }
    func testAdapterPreservesOriginalSlideUnitsAndStableIDsAfterReorder() throws {
        let id = UUID(), other = UUID()
        for (w,h) in [(9144000.0,6858000.0),(12192000.0,6858000.0),(6000000.0,9000000.0)] {
            var adapter = DocumentAdapter(kind: "pptx", originalPath: "x.pptx", originalSHA256: String(repeating: "a", count: 64), width: w, height: h)
            adapter.pageIDs = [other,id]
            let sample = PortableInkSample(x: 260, y: 370, width: 2, height: 4, pressure: 0.5, opacity: 1, timeMs: 0)
            let stroke = PortableInkStroke(id: UUID().uuidString.lowercased(), layerId: "main", tool: "pen", color: "#000000", opacity: 1, createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", transform: [1,0,0,1,0,0], samples: [sample])
            let page = PortableInkPage(id: id.uuidString.lowercased(), kind: "pdf", unit: "pt", bounds: PortableInkBounds(x: 10,y: 20,width: 500,height: 700), rotation: 0, strokes: [stroke])
            let output = try adapter.convert(page,index: 0)
            XCTAssertEqual(output.id,page.id); XCTAssertEqual(output.unit,"emu")
            XCTAssertEqual(output.strokes[0].samples[0].x,w/2,accuracy:0.001)
            XCTAssertEqual(output.strokes[0].samples[0].y,h/2,accuracy:0.001)
        }
    }
    func testReopenAdoptsAnExternalCommitOnlyWhenThePDFHasArrived() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try PDFModel(data: PDFModel.blank(template: .plain)), url = root.appendingPathComponent("note.pdf")
        let first = try model.snapshot(); try first.write(to: url)
        let a = try InkCommitStore(root: root, documentID: model.documentID, documentURL: url); try a.publish(model, fileBytes: first)
        let key = "inkdrive.head." + model.documentID.uuidString
        let oldHead = UserDefaults.standard.string(forKey: key)
        let b = try InkCommitStore(root: root, documentID: model.documentID, documentURL: url)
        _ = try model.insertBlank(at: 1, template: .plain)
        let second = try model.snapshot(); try b.publish(model, fileBytes: second)
        UserDefaults.standard.set(oldHead, forKey: key)
        let pending = try InkCommitStore(root: root, documentID: model.documentID, documentURL: url)
        XCTAssertThrowsError(try pending.checkHead())
        try second.write(to: url)
        let reopened = try InkCommitStore(root: root, documentID: model.documentID, documentURL: url)
        XCTAssertNoThrow(try reopened.checkHead())
    }
    func testLibraryDocumentIdentityIsPersistedOnceBeforeAnyHandwriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), repository = LibraryRepository(defaults: defaults)
        try repository.choose(root)
        let path = try repository.createNote(parent: "", name: "lecture", template: "plain")
        let first = try await repository.open(path)
        XCTAssertTrue(first.dirty); try await first.flush()
        let bytes = try Data(contentsOf: root.appendingPathComponent(path))
        let second = try await repository.open(path)
        XCTAssertFalse(second.dirty); XCTAssertEqual(second.model.documentID, first.model.documentID)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes)
    }
    func testSnapshotRecordingUsesTheOriginalCourseAndMaterial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("통계/강의자료"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), repository = LibraryRepository(defaults: defaults)
        try repository.choose(root)
        let course = CampusCourse(id: 9, fullname: "통계", shortname: "통계 (2026-0020, IE1_066)")
        try JSONEncoder().encode(course).write(to: root.appendingPathComponent("통계/.campus-course.json"))
        let material = "통계/강의자료/자료.pptx", source = Data("original presentation fixture".utf8)
        try source.write(to: root.appendingPathComponent(material))
        let path = try repository.createNote(parent: "", name: "snapshot", template: "plain")
        let adapter = DocumentAdapter(kind: "pptx", originalPath: material, originalSHA256: CoordinatedStore.digest(source), width: 9144000, height: 6858000)
        try JSONEncoder().encode(adapter).write(to: URL(fileURLWithPath: root.appendingPathComponent(path).path + ".adapter.json"))
        let lesson = try repository.quickLesson(pdf: path, date: "2026-10-21")
        XCTAssertEqual(lesson.subject, "통계"); XCTAssertEqual(lesson.title, "자료"); XCTAssertEqual(lesson.courseID, "9")
        XCTAssertEqual(lesson.materials, [material])
    }
}
