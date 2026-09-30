import XCTest

@testable import OrganizerCore

final class OrganizerTests: XCTestCase {
  var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func testCollisionMoveAndUndo() throws {
    let source = root.appendingPathComponent("report.pdf")
    try Data("new".utf8).write(to: source)
    let folder = root.appendingPathComponent("Documents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: folder.appendingPathComponent("report.pdf"))
    let plan = try Organizer.preview(in: root, rules: Rule.defaults)
    XCTAssertTrue(plan[0].destination.hasSuffix("report (2).pdf"))
    try Organizer.apply(plan[0])
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    try Organizer.undo(plan[0])
    XCTAssertEqual(try Data(contentsOf: source), Data("new".utf8))
    XCTAssertEqual(
      try Data(contentsOf: folder.appendingPathComponent("report.pdf")), Data("old".utf8))
  }
  func testChangedFilesAndSymlinksAreNotMoved() throws {
    let source = root.appendingPathComponent("a.txt")
    try Data("before".utf8).write(to: source)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link.txt"), withDestinationURL: source)
    let plan = try Organizer.preview(in: root, rules: Rule.defaults)
    XCTAssertEqual(plan.count, 1)
    try Data("after".utf8).write(to: source)
    XCTAssertThrowsError(try Organizer.apply(plan[0]))
    XCTAssertThrowsError(
      try Organizer.preview(in: root, rules: [Rule(folder: "../out", extensions: "txt")]))
  }
  func testUndoNeverOverwritesOriginal() throws {
    let source = root.appendingPathComponent("a.txt")
    try Data("before".utf8).write(to: source)
    let move = try Organizer.preview(in: root, rules: Rule.defaults)[0]
    try Organizer.apply(move)
    try Data("replacement".utf8).write(to: source)
    XCTAssertThrowsError(try Organizer.undo(move))
    XCTAssertEqual(try Data(contentsOf: source), Data("replacement".utf8))
  }
}
