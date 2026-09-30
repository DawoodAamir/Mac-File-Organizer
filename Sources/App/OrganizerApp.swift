import AppKit
import SwiftUI

@MainActor final class OrganizerStore: ObservableObject {
  @Published var folder: URL?
  @Published var rules = Rule.defaults
  @Published var plan: [Move] = []
  @Published var journal: [Move] = []
  @Published var busy = false
  @Published var error: String?
  @Published var status = "Choose a folder to begin."
  private let file = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      (ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"].map { "UITests/" + $0 + "/" } ?? "")
        + "MacFileOrganizer/journal.json")
  private var accessed = false
  private var canSave = true
  init() {
    if let data = UserDefaults.standard.data(forKey: "rules"),
      let saved = try? JSONDecoder().decode([Rule].self, from: data)
    {
      rules = saved
    }
    if ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"] == nil,
      let data = UserDefaults.standard.data(forKey: "folder")
    {
      do {
        var stale = false
        let url = try URL(
          resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
          bookmarkDataIsStale: &stale)
        accessed = url.startAccessingSecurityScopedResource()
        folder = url
        if stale {
          UserDefaults.standard.set(
            try url.bookmarkData(
              options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
            forKey: "folder")
        }
      } catch { self.error = "Choose your folder again to restore access." }
    }
    do {
      journal = try JSONDecoder().decode([Move].self, from: Data(contentsOf: file))
      status = journal.isEmpty ? "Ready for preview." : "Previous moves available for undo."
    } catch let e as CocoaError where e.code == .fileReadNoSuchFile {} catch {
      canSave = false
      self.error = "Move history could not be read. The original file is preserved."
    }
    if let test = ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(test)
      try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try? Data("Preview fixture".utf8).write(to: root.appendingPathComponent("demo.txt"))
      folder = root
    }

  }
  func choose() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose folder"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if accessed { folder?.stopAccessingSecurityScopedResource() }
    accessed = url.startAccessingSecurityScopedResource()
    folder = url
    plan = []
    do {
      UserDefaults.standard.set(
        try url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
        forKey: "folder")
    } catch { self.error = error.localizedDescription }
  }
  func preview() async {
    guard let folder, !busy else { return }
    busy = true
    defer { busy = false }
    let selectedRules = rules
    do {
      plan = try await Task.detached(priority: .userInitiated) {
        try Organizer.preview(in: folder, rules: selectedRules)
      }.value
      UserDefaults.standard.set(try JSONEncoder().encode(rules), forKey: "rules")
      status =
        plan.isEmpty
        ? "No files match your rules."
        : "\(plan.count) \(plan.count == 1 ? "move" : "moves") ready for review."
    } catch { self.error = error.localizedDescription }
  }
  private func saveJournal(_ next: [Move]) throws {
    guard canSave else { throw CocoaError(.fileWriteNoPermission) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(next).write(to: file, options: .atomic)
    journal = next
  }
  func apply() async {
    guard !busy, canSave else { return }
    busy = true
    defer { busy = false }
    do {
      for move in plan {
        // Write intent first so a crash after the move still leaves a recoverable journal.
        try saveJournal(journal + [move])
        do { try await Task.detached { try Organizer.apply(move) }.value } catch {
          try? saveJournal(journal.filter { $0.id != move.id })
          throw error
        }
      }
      plan = []
      status = "Files organised. Undo is available."
    } catch {
      plan = []
      self.error = error.localizedDescription
      status = "Stopped. Completed moves remain available for undo."
    }
  }
  func undo() async {
    guard !busy, canSave else { return }
    busy = true
    defer { busy = false }
    do {
      while let move = journal.last {
        guard let folder,
          URL(fileURLWithPath: move.source).deletingLastPathComponent().standardizedFileURL
            == folder.standardizedFileURL
        else {
          throw NSError(domain: "Choose the original folder before undoing these moves.", code: 1)
        }
        let destination = URL(fileURLWithPath: move.destination)
        let source = URL(fileURLWithPath: move.source)
        if FileManager.default.fileExists(atPath: destination.path) {
          try await Task.detached { try Organizer.undo(move) }.value
        } else {
          guard try Organizer.fingerprint(source) == move.digest else {
            throw OrganizerError.missingFile
          }
        }
        try saveJournal(Array(journal.dropLast()))
      }
      plan = []
      status = "All recorded moves restored."
    } catch { self.error = error.localizedDescription }
  }
}
@main struct OrganizerApp: App {
  @StateObject var store = OrganizerStore()
  var body: some Scene {
    WindowGroup {
      OrganizerView().environmentObject(store).frame(minWidth: 780, minHeight: 580).tint(.indigo)
    }.commands {
      CommandGroup(after: .newItem) {
        Button("Choose Folder…") { store.choose() }.keyboardShortcut("o")
      }
    }
  }
}
struct OrganizerView: View {
  @EnvironmentObject var store: OrganizerStore
  @State var confirm = false
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 20) {
        Label("File Organizer", systemImage: "folder").font(.title2.weight(.semibold))
        Text("RULES").font(.caption.weight(.semibold)).foregroundColor(.secondary)
        ScrollView {
          VStack(spacing: 16) {
            ForEach($store.rules) { $rule in
              VStack(alignment: .leading, spacing: 6) {
                TextField("Folder", text: $rule.folder)
                TextField("Extensions, comma separated", text: $rule.extensions).font(.caption)
              }.textFieldStyle(.roundedBorder)
            }
          }
        }
        Text(
          "Only files directly inside your chosen folder are considered. Hidden files, folders, and symbolic links are skipped."
        ).font(.caption).foregroundColor(.secondary)
        Button("Add rule") { store.rules.append(Rule(folder: "New folder", extensions: "")) }
      }.padding(24).frame(width: 240).background(Color(NSColor.controlBackgroundColor))
      Divider()
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Keep your files in order.").font(.largeTitle.weight(.semibold))
            Text(store.folder?.lastPathComponent ?? "Select the folder you want to organise.").font(
              .subheadline
            )
            .foregroundColor(.secondary).textSelection(.enabled)
          }
          Spacer()
          Button("Choose Folder…") { store.choose() }
        }
        HStack {
          Label("Preview every move", systemImage: "list.bullet.rectangle")
          Spacer()
          Label("Existing files preserved", systemImage: "checkmark.shield")
        }.font(.caption).foregroundColor(.secondary)
        Divider()
        if store.plan.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape").font(.system(size: 44)).foregroundColor(
              .secondary)
            Text(store.status).font(.headline)
            Text("Set your rules, then preview the destinations before moving anything.")
              .foregroundColor(.secondary).multilineTextAlignment(.center)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(store.plan) { move in
            VStack(alignment: .leading, spacing: 6) {
              Text(URL(fileURLWithPath: move.source).lastPathComponent).font(.headline)
              Label(
                URL(fileURLWithPath: move.destination).deletingLastPathComponent().lastPathComponent
                  + "/" + URL(fileURLWithPath: move.destination).lastPathComponent,
                systemImage: "arrow.turn.down.right"
              ).font(.caption).foregroundColor(.secondary)
            }.padding(.vertical, 6)
          }
        }
        HStack {
          if store.busy { ProgressView().controlSize(.small) }
          Text(store.status).font(.caption).foregroundColor(.secondary)
          Spacer()
          Button("Undo \(store.journal.count) moves") { Task { await store.undo() } }.disabled(
            store.journal.isEmpty || store.busy)
          Button("Preview") { Task { await store.preview() } }.disabled(
            store.folder == nil || store.busy)
          Button("Move files") { confirm = true }.buttonStyle(.borderedProminent).disabled(
            store.plan.isEmpty || store.busy)
        }
      }.padding(28)
    }.alert(
      "Move \(store.plan.count) \(store.plan.count == 1 ? "file" : "files")?", isPresented: $confirm
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Move files") { Task { await store.apply() } }
    } message: {
      Text(
        "Files will move to the folders shown in your preview. You can undo unchanged files afterwards."
      )
    }
    .alert(
      "Organiser needs attention",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
}
