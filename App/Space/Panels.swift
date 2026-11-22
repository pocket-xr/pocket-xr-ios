import PocketXRCore
import UIKit

private let ink = UIColor.white.withAlphaComponent(0.92)
private let ink2 = UIColor.white.withAlphaComponent(0.64)
private let card = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
private let control = UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1)
private let accent = UIColor(red: 0.35, green: 0.58, blue: 1, alpha: 1)

@MainActor
private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = ink) -> UILabel {
    let l = UILabel()
    l.text = L(text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
}

@MainActor
private func pill(_ title: String, symbol: String? = nil, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
    var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
    config.title = L(title)
    if let s = symbol {
        config.image = UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        config.imagePadding = 10
    }
    config.baseBackgroundColor = filled ? accent : control
    config.baseForegroundColor = ink
    config.cornerStyle = .large
    config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
        var a = a
        a.font = .systemFont(ofSize: 24, weight: .semibold)
        return a
    }
    return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
}

/// A site in the launcher.
struct LauncherSite: Codable, Equatable {
    var name: String
    var url: String
    var symbol: String

    /// Not a site: opens the next PC screen.
    static let pcScreen = "pocketxr:pcscreen"
    /// Not a site: PC VR (SteamVR games from a Windows PC).
    static let pcVr = "pocketxr:pcvr"

    static let defaults: [LauncherSite] = [
        LauncherSite(name: "PC VR", url: LauncherSite.pcVr, symbol: "gamecontroller.fill"),
        LauncherSite(name: "PC screen", url: LauncherSite.pcScreen, symbol: "desktopcomputer"),
        LauncherSite(name: "Google", url: "https://www.google.com", symbol: "magnifyingglass"),
        LauncherSite(name: "YouTube", url: "https://m.youtube.com", symbol: "play.rectangle.fill"),
        LauncherSite(name: "Gmail", url: "https://mail.google.com", symbol: "envelope.fill"),
        LauncherSite(name: "Docs", url: "https://docs.google.com", symbol: "doc.text.fill"),
        LauncherSite(name: "Wikipedia", url: "https://en.m.wikipedia.org", symbol: "book.fill"),
        LauncherSite(name: "Test page", url: TestPage.url, symbol: "checkmark.seal.fill"),
    ]
}

/// The launcher: a search or address field, the time and battery, and a grid of sites. Opening a site opens a new
/// web window; an address or search typed into the field and Enter opens that.
final class LauncherPanel: PanelContent {
    override var title: String { "Apps" }
    private let field = UITextField()
    private let clock = UILabel()
    private var timer: Timer?
    /// The tiles, for the self-test to aim at.
    private(set) var tiles = [UIButton]()

    init(sites: [LauncherSite], open: @escaping (String) -> Void) {
        super.init()
        root.backgroundColor = UIColor(red: 0.05, green: 0.055, blue: 0.065, alpha: 1)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
        ])
        let top = UIStackView(arrangedSubviews: [label("Pocket XR", size: 30, weight: .bold), UIView(), clock])
        top.axis = .horizontal
        clock.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        clock.textColor = ink2
        stack.addArrangedSubview(top)

        field.placeholder = L("Search or type an address")
        field.attributedPlaceholder = NSAttributedString(string: L("Search or type an address"), attributes: [.foregroundColor: ink2])
        field.font = .systemFont(ofSize: 26)
        field.textColor = ink
        field.backgroundColor = control
        field.layer.cornerRadius = 16
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 64).isActive = true
        field.addAction(UIAction { [weak self] _ in
            guard let self = self, let text = self.field.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            open(Self.address(for: text))
            self.field.text = ""
        }, for: .editingDidEndOnExit)
        stack.addArrangedSubview(field)
        typingTarget = field

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 16
        grid.distribution = .fillEqually
        var row: UIStackView?
        for (i, site) in sites.enumerated() {
            if i % 4 == 0 {
                let r = UIStackView()
                r.axis = .horizontal
                r.spacing = 16
                r.distribution = .fillEqually
                grid.addArrangedSubview(r)
                row = r
            }
            var config = UIButton.Configuration.gray()
            config.title = L(site.name)
            config.image = UIImage(systemName: site.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .medium))
            config.imagePlacement = .top
            config.imagePadding = 12
            config.baseBackgroundColor = card
            config.baseForegroundColor = ink
            config.cornerStyle = .large
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a
                a.font = .systemFont(ofSize: 22, weight: .medium)
                return a
            }
            let b = UIButton(configuration: config, primaryAction: UIAction { _ in open(site.url) })
            b.heightAnchor.constraint(equalToConstant: 150).isActive = true
            b.accessibilityLabel = site.name
            tiles.append(b)
            row?.addArrangedSubview(b)
        }
        while let r = row, r.arrangedSubviews.count < 4 { r.addArrangedSubview(UIView()) }
        stack.addArrangedSubview(grid)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    private func tick() {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM  HH:mm"
        var text = f.string(from: Date())
        let level = UIDevice.current.batteryLevel
        if level >= 0 { text += String(format: "   %.0f %%", level * 100) }
        clock.text = text
    }

    /// What typing in the launcher opens: an address as it is (with https:// added), anything else as a search.
    static func address(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.contains(" ") || !t.contains(".") {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: t)]
            return c.url?.absoluteString ?? "https://www.google.com"
        }
        return t.lowercased().hasPrefix("http") ? t : "https://" + t
    }
}

/// The Control Center: arrange layouts, recentre, Lock screens, Adjust all, layouts saved as presets, and status.
final class ControlCenterPanel: PanelContent {
    override var title: String { "Control Center" }
    private let lockSwitch = UISwitch()
    private let trackingSwitch = UISwitch()
    private let readabilitySwitch = UISwitch()
    private let followControl = UISegmentedControl(items: [L("Stay in place"), L("Smooth Follow")])
    private let shapeRow = UIStackView()
    private let shapeTitle = UILabel()
    private let status = UILabel()
    private let arrangeRow = UIStackView()
    private let presetRow = UIStackView()
    private weak var controller: SpaceController?

    init(controller: SpaceController) {
        self.controller = controller
        super.init()
        root.backgroundColor = UIColor(red: 0.05, green: 0.055, blue: 0.065, alpha: 1)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
        ])
        stack.addArrangedSubview(label("Control Center", size: 30, weight: .bold))
        status.font = .systemFont(ofSize: 22)
        status.textColor = ink2
        status.numberOfLines = 2
        stack.addArrangedSubview(status)

        stack.addArrangedSubview(label("Arrange", size: 22, weight: .semibold, color: ink2))
        arrangeRow.axis = .horizontal
        arrangeRow.spacing = 12
        arrangeRow.distribution = .fillEqually
        stack.addArrangedSubview(arrangeRow)

        let quick = UIStackView(arrangedSubviews: [
            pill("Recentre", symbol: "scope") { controller.recentre() },
            pill("Adjust all", symbol: "arrow.up.and.down.and.arrow.left.and.right") { controller.setMode(.moveAll) },
            pill("Close all", symbol: "xmark.circle") { controller.closeAll() },
        ])
        let modes = UIStackView(arrangedSubviews: [
            pill("Steady mode", symbol: "rectangle.split.3x1") { controller.setSteady(!controller.steady) },
            pill("Record", symbol: "record.circle") { controller.setRecording(!controller.recording) },
        ])
        modes.axis = .horizontal
        modes.spacing = 12
        modes.distribution = .fillEqually
        quick.axis = .horizontal
        quick.spacing = 12
        quick.distribution = .fillEqually
        stack.addArrangedSubview(quick)
        stack.addArrangedSubview(modes)

        let lockRow = UIStackView(arrangedSubviews: [label("Lock screens", size: 24), UIView(), lockSwitch])
        lockRow.axis = .horizontal
        lockSwitch.onTintColor = accent
        lockSwitch.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            controller.setLocked(self.lockSwitch.isOn)
        }, for: .valueChanged)
        stack.addArrangedSubview(lockRow)

        let trackRow = UIStackView(arrangedSubviews: [label("Head tracking", size: 24), UIView(), followControl, trackingSwitch])
        trackRow.axis = .horizontal
        trackRow.spacing = 16
        trackingSwitch.onTintColor = accent
        trackingSwitch.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            controller.setHeadTracking(self.trackingSwitch.isOn)
        }, for: .valueChanged)
        followControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: ink], for: .normal)
        followControl.selectedSegmentTintColor = accent
        followControl.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            controller.setFollow(self.followControl.selectedSegmentIndex == 1)
        }, for: .valueChanged)
        stack.addArrangedSubview(trackRow)

        let readRow = UIStackView(arrangedSubviews: [label("Readability: larger text", size: 24), UIView(), readabilitySwitch])
        readRow.axis = .horizontal
        readabilitySwitch.onTintColor = accent
        readabilitySwitch.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            controller.setReadability(self.readabilitySwitch.isOn)
        }, for: .valueChanged)
        stack.addArrangedSubview(readRow)

        shapeTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        shapeTitle.textColor = ink2
        stack.addArrangedSubview(shapeTitle)
        shapeRow.axis = .horizontal
        shapeRow.spacing = 10
        shapeRow.distribution = .fillEqually
        for s in WindowShape.allCases {
            shapeRow.addArrangedSubview(pill(s.rawValue) { controller.shapeFocused(s) })
        }
        stack.addArrangedSubview(shapeRow)

        stack.addArrangedSubview(label("Presets", size: 22, weight: .semibold, color: ink2))
        presetRow.axis = .horizontal
        presetRow.spacing = 12
        presetRow.distribution = .fillEqually
        stack.addArrangedSubview(presetRow)
        refresh()
    }

    /// For the self-test.
    var lockSwitchForTest: UISwitch { lockSwitch }
    var readabilitySwitchForTest: UISwitch { readabilitySwitch }
    func shapeButtonForTest(_ s: WindowShape) -> UIButton? {
        guard let i = WindowShape.allCases.firstIndex(of: s), i < shapeRow.arrangedSubviews.count else { return nil }
        return shapeRow.arrangedSubviews[i] as? UIButton
    }

    /// Brings the panel up to date with the Space (called when it changes).
    func refresh() {
        guard let c = controller else { return }
        lockSwitch.isOn = c.space.locked
        trackingSwitch.isOn = c.tracking.headTracking
        readabilitySwitch.isOn = c.readability
        followControl.selectedSegmentIndex = c.tracking.trackingMode == .smoothFollow ? 1 : 0
        if let w = c.focusedWeb {
            let now = WindowShape.current(width: w.layoutWidth, height: w.layoutHeight - Double(WindowHost.barHeight))
            shapeTitle.text = String(format: L("This window: %@"), w.title) + (now.map { "  (\($0.rawValue))" } ?? "")
            shapeRow.isHidden = false
        } else {
            shapeTitle.text = L("This window: click a web window first")
            shapeRow.isHidden = true
        }
        let webCount = c.space.windows.filter { w in
            switch w.kind {
            case .web, .pcScreen: return true
            default: return false
            }
        }.count
        let tracking = L(c.tracked ? "Head tracking on"
            : (Probe.shared.snapshot.link == .streaming ? "Head tracking off" : "No head tracking (drag the pointer to the edge to look around)"))
        status.text = String(format: L("Windows: %@"), "\(webCount)") + "   " + tracking
        arrangeRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let count = max(1, min(3, webCount))
        for layout in SpaceLayout.choices(count: count) {
            arrangeRow.addArrangedSubview(pill(SpaceLayout.title(layout, count: count)) { c.arrange(layout) })
        }
        presetRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        presetRow.addArrangedSubview(pill("Save layout", symbol: "square.and.arrow.down", filled: true) { c.savePreset() })
        for (i, p) in c.presets.prefix(3).enumerated() {
            presetRow.addArrangedSubview(pill(p.name) { c.applyPreset(i) })
        }
    }
}
