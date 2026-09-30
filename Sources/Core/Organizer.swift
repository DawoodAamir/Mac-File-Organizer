import CryptoKit
import Foundation

struct Move: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  let source: String
  let destination: String
  let digest: String
}
struct Rule: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var folder: String
  var extensions: String
  static let defaults = [
    Rule(folder: "Images", extensions: "jpg,jpeg,png,heic,gif"),
    Rule(folder: "Documents", extensions: "pdf,txt,docx,csv"),
    Rule(folder: "Audio", extensions: "mp3,m4a,wav"),
    Rule(folder: "Archives", extensions: "zip,gz"),
  ]
}
enum OrganizerError: LocalizedError {
  case unsafeRule, changedFile, missingFile
  var errorDescription: String? {
    switch self {
    case .unsafeRule: return "Use a folder name without slashes, dots, or reserved path characters."
    case .changedFile:
      return "A file changed since preview, or its destination is occupied. Preview again."
    case .missingFile: return "A file is missing or is a symbolic link."
    }
  }
}
struct Organizer {
  static func fingerprint(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw OrganizerError.missingFile
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
  static func preview(in root: URL, rules: [Rule]) throws -> [Move] {
    for rule in rules {
      guard !rule.folder.isEmpty, !rule.folder.hasPrefix("."), !rule.folder.contains("/"),
        !rule.folder.contains(":"), !rule.folder.contains("\\")
      else { throw OrganizerError.unsafeRule }
    }
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    ).sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
    var reserved = Set<String>()
    var result: [Move] = []
    for source in files {
      let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      guard
        let rule = rules.first(where: {
          $0.extensions.lowercased().split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
          }.contains(source.pathExtension.lowercased())
        })
      else { continue }
      let directory = root.appendingPathComponent(rule.folder, isDirectory: true)
      if fm.fileExists(atPath: directory.path) {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
          throw OrganizerError.unsafeRule
        }
      }
      var destination = directory.appendingPathComponent(source.lastPathComponent)
      var suffix = 2
      while reserved.contains(destination.path) || fm.fileExists(atPath: destination.path) {
        let ext = source.pathExtension
        destination = directory.appendingPathComponent(
          source.deletingPathExtension().lastPathComponent + " (\(suffix))"
            + (ext.isEmpty ? "" : "." + ext))
        suffix += 1
      }
      reserved.insert(destination.path)
      result.append(
        Move(source: source.path, destination: destination.path, digest: try fingerprint(source)))
    }
    return result
  }
  static func apply(_ move: Move) throws {
    let source = URL(fileURLWithPath: move.source)
    let destination = URL(fileURLWithPath: move.destination)
    let directory = destination.deletingLastPathComponent()
    let fm = FileManager.default
    guard try fingerprint(source) == move.digest, !fm.fileExists(atPath: destination.path) else {
      throw OrganizerError.changedFile
    }
    if fm.fileExists(atPath: directory.path) {
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw OrganizerError.unsafeRule
      }
    } else {
      try fm.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    try fm.moveItem(at: source, to: destination)
  }
  static func undo(_ move: Move) throws {
    let fm = FileManager.default
    let source = URL(fileURLWithPath: move.source)
    let destination = URL(fileURLWithPath: move.destination)
    guard try fingerprint(destination) == move.digest, !fm.fileExists(atPath: source.path) else {
      throw OrganizerError.changedFile
    }
    try fm.moveItem(at: destination, to: source)
  }
}
