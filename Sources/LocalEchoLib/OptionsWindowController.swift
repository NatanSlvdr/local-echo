import AppKit

// Hosts the menu bar app's settings in a regular window so AppKit can render native controls.
final class OptionsWindowController: NSWindowController, NSWindowDelegate {
    private let onConfigChange: (Config) -> Void
    private let modelPopup = NSPopUpButton()
    private let audioPopup = NSPopUpButton()
    private let toggleSwitch = NSSwitch()
    private let duckSwitch = NSSwitch()
    private let hotkeyValue = NSTextField(labelWithString: "")
    private var inputDevices: [AudioInputDevice] = []

    init(onConfigChange: @escaping (Config) -> Void) {
        self.onConfigChange = onConfigChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 370),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Options"
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func buildContent() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let heading = NSTextField(labelWithString: "Options")
        heading.font = .boldSystemFont(ofSize: 22)
        stack.addArrangedSubview(heading)

        stack.addArrangedSubview(sectionLabel("Recognition"))
        modelPopup.addItems(withTitles: Config.supportedModels)
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        addRow("Model", control: modelPopup, to: stack)

        audioPopup.target = self
        audioPopup.action = #selector(audioChanged(_:))
        addRow("Audio Input", control: audioPopup, to: stack)

        stack.addArrangedSubview(sectionLabel("Recording"))
        hotkeyValue.textColor = .secondaryLabelColor
        addRow("Hotkey", control: hotkeyValue, to: stack)

        toggleSwitch.target = self
        toggleSwitch.action = #selector(toggleModeChanged(_:))
        toggleSwitch.setAccessibilityLabel("Toggle Mode")
        addRow("Toggle Mode", control: toggleSwitch, to: stack)

        duckSwitch.target = self
        duckSwitch.action = #selector(duckAudioChanged(_:))
        duckSwitch.setAccessibilityLabel("Lower Other Audio While Recording")
        addRow("Lower Other Audio While Recording", control: duckSwitch, to: stack)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let openButton = NSButton(title: "Open Configuration", target: self, action: #selector(openConfiguration))
        let reloadButton = NSButton(title: "Reload Configuration", target: self, action: #selector(reloadConfiguration))
        buttons.addArrangedSubview(openButton)
        buttons.addArrangedSubview(reloadButton)
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            modelPopup.widthAnchor.constraint(equalToConstant: 235),
            audioPopup.widthAnchor.constraint(equalToConstant: 235),
        ])
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func addRow(_ title: String, control: NSView, to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.addArrangedSubview(NSTextField(labelWithString: title))
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(control)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func refresh(config: Config, isRecording: Bool) {
        modelPopup.selectItem(withTitle: config.modelSize)
        hotkeyValue.stringValue = config.hotkeySummary()
        toggleSwitch.state = (config.toggleMode?.value ?? false) ? .on : .off
        duckSwitch.state = config.duckOtherAudioEnabled ? .on : .off
        if #available(macOS 14.0, *) {
            duckSwitch.isEnabled = !isRecording
        } else {
            duckSwitch.isEnabled = false
        }

        inputDevices = AudioDeviceManager.listInputDevices()
        audioPopup.removeAllItems()
        audioPopup.addItem(withTitle: "System Default")
        audioPopup.addItems(withTitles: inputDevices.map(\.name))
        let selectedIndex = inputDevices.firstIndex { device in
            if let uid = config.audioInputDeviceUID { return device.uid == uid }
            if let id = config.audioInputDeviceID { return device.id == id }
            return false
        }
        audioPopup.selectItem(at: selectedIndex.map { $0 + 1 } ?? 0)
    }

    private func saveChange(_ change: (inout Config) -> Void) {
        var config = Config.load()
        change(&config)
        do {
            try config.save()
            onConfigChange(config)
        } catch {
            let alert = NSAlert(error: error)
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let model = sender.selectedItem?.title else { return }
        saveChange { $0.modelSize = model }
    }

    @objc private func audioChanged(_ sender: NSPopUpButton) {
        let device = inputDevices.indices.contains(sender.indexOfSelectedItem - 1)
            ? inputDevices[sender.indexOfSelectedItem - 1] : nil
        saveChange {
            $0.audioInputDeviceID = device?.id
            $0.audioInputDeviceUID = device?.uid
        }
    }

    @objc private func toggleModeChanged(_ sender: NSSwitch) {
        saveChange { $0.toggleMode = FlexBool(sender.state == .on) }
    }

    @objc private func duckAudioChanged(_ sender: NSSwitch) {
        saveChange { $0.duckOtherAudioDuringRecording = FlexBool(sender.state == .on) }
    }

    @objc private func openConfiguration() {
        let configFile = Config.configFile
        if !FileManager.default.fileExists(atPath: configFile.path) {
            try? Config.defaultConfig.save()
        }
        NSWorkspace.shared.open(configFile)
    }

    @objc private func reloadConfiguration() {
        (NSApplication.shared.delegate as? AppDelegate)?.reloadConfig()
    }
}
