import PocketXRCore
import SwiftUI
import UniformTypeIdentifiers

/// A JSON file for the share sheet and Files: settings or layouts.
struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Pocket XR's settings on the phone: Steady mode and Record, the glasses and tracking, the setup check and tour, and
/// settings and layouts to and from files.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var space = SpaceController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exporting: JSONFile?
    @State private var exportName = ""
    @State private var showExport = false
    @State private var importing: ImportKind?
    @State private var message = ""
    @State private var showTour = false
    @State private var showCheck = false

    enum ImportKind { case settings, layouts }

    var body: some View {
        NavigationStack {
            List {
                Section("The Space") {
                    Toggle("Steady mode", isOn: Binding(get: { space.steady }, set: { space.setSteady($0) }))
                    Toggle("Record the glasses", isOn: Binding(get: { space.recording }, set: { space.setRecording($0) }))
                    Toggle("Readability: larger text", isOn: Binding(get: { space.readability }, set: { space.setReadability($0) }))
                    Toggle("Head tracking", isOn: Binding(get: { space.tracking.headTracking }, set: { space.setHeadTracking($0) }))
                }
                Section("Glasses") {
                    Button("Glasses setup check") { showCheck = true }
                    NavigationLink("Glasses and head tracking details") { ProbeView().environmentObject(model) }
                }
                Section("Help and more") {
                    Button("Tour of Pocket XR") { showTour = true }
                    Button("Save settings to a file") { export(space.settingsFile(), name: "Pocket XR settings") }
                    Button("Restore settings from a file") { importing = .settings }
                    Button("Share layouts") { export(space.layoutsFile(), name: "Pocket XR layouts") }
                    Button("Import layouts") { importing = .layouts }
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Text("Pocket XR \(AppInfo.version) (\(AppInfo.build))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .fileExporter(isPresented: $showExport, document: exporting, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let e) = result { message = e.localizedDescription } else { message = L("Saved.") }
        }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: [.json]) { result in
            let kind = importing
            importing = nil
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { message = L("That file could not be read."); return }
            switch kind {
            case .settings:
                message = L(space.restoreSettings(data) ? "Settings restored." : "That is not a Pocket XR settings file.")
            case .layouts:
                message = space.importLayouts(data).map { String(format: L("Layouts imported: %@"), "\($0)") } ?? L("That is not a Pocket XR layouts file.")
            case nil:
                break
            }
        }
        .sheet(isPresented: $showTour) { TourView() }
        .sheet(isPresented: $showCheck) { SetupCheckView().environmentObject(model) }
    }

    private func export(_ data: Data?, name: String) {
        guard let data else { message = L("Nothing to save."); return }
        exporting = JSONFile(data: data)
        exportName = name
        showExport = true
    }
}

/// The glasses setup check: only the steps the user's glasses need, and what iOS lets Pocket XR do with them. iOS
/// cannot tell which glasses are plugged in, so the user picks them.
struct SetupCheckView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("setup.glasses") private var glasses = "aura"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Your glasses", selection: $glasses) {
                        Text("XREAL Aura").tag("aura")
                        Text("XREAL One, One Pro, 1S").tag("one")
                        Text("XREAL Air family").tag("air")
                        Text("VITURE Beast").tag("beast")
                        Text("Other glasses").tag("other")
                    }
                }
                Section("Right now") {
                    Label(model.display.connected ? "Glasses connected as a screen" : "No glasses connected as a screen",
                          systemImage: model.display.connected ? "checkmark.circle.fill" : "xmark.circle")
                    Label(model.probe.link == .streaming ? "Head tracking from the glasses" : "No head tracking from the glasses",
                          systemImage: model.probe.link == .streaming ? "checkmark.circle.fill" : "xmark.circle")
                }
                Section("Steps") {
                    ForEach(steps, id: \.self) { Text(L($0)) }
                }
            }
            .navigationTitle("Glasses setup check")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var steps: [String] {
        switch glasses {
        case "aura":
            return ["Nothing to set on the glasses: Pocket XR sets the Aura's display itself, when iOS lets it reach the glasses' USB link.",
                    "Head tracking needs that link. If the line above says no head tracking, use Steady mode: the glasses hold the picture."]
        case "one":
            return ["Press X on the glasses once and pick Follow mode, not Anchor.",
                    "Press X twice for the glasses' menu: Spatial Screen, Stabilizer, off.",
                    "Without head tracking on this iPhone, use Anchor mode instead and turn on Steady mode in Pocket XR: the glasses hold the picture."]
        case "air":
            return ["iOS does not let apps read the Air family's motion sensor, so there is no head tracking on iPhone.",
                    "The windows stay in front of you; drag the pointer to the edge of the view to look around."]
        case "beast":
            return ["iOS does not let apps read the Beast's motion sensor. Use the Beast's own 3DoF hold and turn on Steady mode in Pocket XR."]
        default:
            return ["Pocket XR shows the Space on any glasses that act as a screen. Head tracking depends on the glasses; send a report from Glasses and head tracking details."]
        }
    }
}

/// The tour: what Pocket XR is and how to use it, shown once on first start and any time from Settings.
struct TourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    static let pages: [(symbol: String, title: String, text: String)] = [
        ("eyeglasses", "Welcome to Pocket XR", "A spatial workspace for your XR glasses, run from this iPhone or iPad. Plug the glasses into the USB-C port and the Space opens on them."),
        ("rectangle.3.group", "Windows around you", "Web pages and your computer's screens float around you as windows. Move them, resize them, push them back or pull them closer."),
        ("hand.point.up.left", "The phone is your trackpad", "Move one finger to move the pointer, tap to click, two fingers to scroll, pinch to resize. Three-finger swipes go between windows."),
        ("dot.radiowaves.up.forward", "Point the phone", "Turn on Pointer and aim the phone like a laser. A Bluetooth mouse and keyboard work too."),
        ("square.grid.2x2", "Apps and the Control Center", "Apps opens the launcher: sites, a search, and PC screen. Control opens the Control Center: arrange, Lock screens, Steady mode, Record."),
        ("desktopcomputer", "Your computer's screens", "With Pocket XR on your Windows PC, Mac or Steam Deck, or with Apollo or Sunshine, open PC screen to see its desktop in the glasses. Up to three at once."),
        ("textformat.size", "Readability", "Larger text on 1080p glasses: web pages and PC screens get a third bigger. In the Control Center."),
        ("rectangle.split.3x1", "Steady mode", "For reading and working: the windows line up in front of you and the glasses hold the picture still."),
        ("checkmark.circle", "Ready", "Plug in your glasses. If something is not right, the Glasses setup check in Settings shows what to set."),
    ]

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    let p = Self.pages[i]
                    VStack(spacing: 18) {
                        Image(systemName: p.symbol).font(.system(size: 64)).foregroundStyle(Color.accentColor)
                        Text(L(p.title)).font(.title2.bold())
                        Text(L(p.text)).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button(L(page == Self.pages.count - 1 ? "Start" : "Next")) {
                if page == Self.pages.count - 1 { finish() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            Button("Skip the tour") { finish() }.font(.footnote)
        }
        .padding(.bottom, 24)
        .preferredColorScheme(.dark)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "tour.seen")
        dismiss()
    }
}
