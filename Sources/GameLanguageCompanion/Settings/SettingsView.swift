import SwiftUI

struct SettingsView: View {
    let appState: AppState
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var permissions: PermissionManager
    @ObservedObject private var status: StatusMonitor

    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginMessage = ""

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _status = ObservedObject(wrappedValue: appState.status)
    }

    var body: some View {
        Form {
            generalSection
            languagesSection
            translationSection
            captureSection
            monitoringSection
            overlaySection
            learningSection
            Section(tr("Anki (via AnkiConnect, localhost)")) {
                AnkiSettingsSection(settings: settings, status: status)
            }
            hotkeySection
            privacySection
            advancedSection
        }
        .formStyle(.grouped)
    }

    // MARK: General

    private var generalSection: some View {
        Section(tr("General")) {
            Picker(tr("Interface language"), selection: $settings.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0) }
            }
            Toggle(tr("Launch at Login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LoginItem.set(newValue)
                        loginMessage = ""
                    } catch {
                        loginMessage = tr("Couldn’t change the login item: %@", error.localizedDescription)
                        launchAtLogin = LoginItem.isEnabled
                    }
                }
            if !loginMessage.isEmpty {
                Text(loginMessage).font(.caption).foregroundStyle(.red)
            }
            Toggle(tr("Show Menu Bar Icon"), isOn: $showMenuBarIcon)
            TextField(tr("Game name (optional)"), text: $settings.gameNameOverride,
                      prompt: Text(tr("Defaults to the frontmost app")))
            Picker(tr("Mode"), selection: $settings.mode) {
                ForEach(LearningMode.allCases) { Text($0.title).tag($0) }
            }
            Text(settings.mode.explanation).font(.caption).foregroundStyle(.secondary)
            Button(tr("Run Setup Again")) { appState.showOnboarding() }
        }
    }

    // MARK: Languages

    private var languagesSection: some View {
        Section(tr("Languages")) {
            Picker(tr("Game language"), selection: $settings.sourceLanguage) {
                ForEach(Language.all) { Text($0.displayName).tag($0) }
            }
            Picker(tr("Translate Into"), selection: $settings.targetLanguage) {
                ForEach(Language.all) { Text($0.displayName).tag($0) }
            }
            Picker(tr("OCR language"), selection: $settings.ocrLanguageCode) {
                Text(tr("Same as game language")).tag("")
                ForEach(Language.all) { Text($0.displayName).tag($0.code) }
            }
        }
    }

    // MARK: Translation

    private var translationSection: some View {
        Section(tr("Translation")) {
            Picker(tr("Provider"), selection: $settings.translationProvider) {
                ForEach(TranslationProviderChoice.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Text(tr("Provider status")).foregroundStyle(.secondary)
                Spacer()
                StatusLabel(item: status.translation)
            }
            if let api = settings.translationProvider.apiProvider {
                ProviderKeyEditor(provider: api, settings: settings) {
                    Task { await status.refresh(settings: settings, force: true) }
                }
                .id(api)
            }
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                AppleTranslationSetupSection(settings: settings)
            }
            #endif
            Text(tr("Only the recognized text is translated — screenshots never leave your Mac. Apple Translation runs fully on-device; the local server option talks to localhost only. DeepL and OpenAI are optional: pick one above and add your own key; if it fails, the app falls back to the free providers."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: settings.translationProvider) { await status.refresh(settings: settings, force: true) }
    }

    // MARK: Capture

    private var captureSection: some View {
        Section(tr("Dialogue Area")) {
            HStack {
                Image(systemName: permissions.hasScreenRecordingAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissions.hasScreenRecordingAccess ? .green : .orange)
                Text(permissions.hasScreenRecordingAccess
                     ? tr("Screen Recording permission granted")
                     : tr("Screen Recording permission missing"))
                Spacer()
                if !permissions.hasScreenRecordingAccess {
                    Button(tr("Open System Settings")) { permissions.openSystemSettings() }
                }
            }
            HStack {
                Text(settings.captureRegion.map { tr("Dialogue area: %@", $0.summary) } ?? tr("No dialogue area selected"))
                Spacer()
                Button(tr("Select…")) { appState.selectCaptureArea() }
                if settings.captureRegion != nil {
                    Button(tr("Clear")) { settings.captureRegion = nil }
                }
            }
            OCRTestPanel(appState: appState, settings: settings)
        }
    }

    // MARK: Monitoring

    private var monitoringSection: some View {
        Section(tr("Monitoring")) {
            Toggle(tr("Monitor the dialogue area"), isOn: $settings.monitoringEnabled)
            HStack {
                Text(tr("Checks per second"))
                Slider(value: $settings.monitoringFrequency, in: 1...4, step: 1)
                Text("\(Int(settings.monitoringFrequency))").frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text(tr("Text stability delay"))
                Slider(value: $settings.stabilityDelay, in: 0.2...1.5, step: 0.1)
                Text(String(format: "%.1f s", settings.stabilityDelay)).frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text(tr("OCR cooldown"))
                Slider(value: $settings.ocrCooldown, in: 0.2...2, step: 0.1)
                Text(String(format: "%.1f s", settings.ocrCooldown)).frame(width: 50, alignment: .trailing)
            }
            Toggle(tr("Save Dialogue History"), isOn: $settings.saveHistory)
            HStack {
                Text(tr("Subtitle text size"))
                Slider(value: $settings.subtitleFontSize, in: 14...40, step: 1)
                Text("\(Int(settings.subtitleFontSize))").frame(width: 50, alignment: .trailing)
            }
            Toggle(tr("Show subtitles above the dialogue"), isOn: $settings.subtitlesAbove)
            Text(tr("Only the dialogue area is watched, and only while the text changes. Frames stay in memory and are never saved."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Overlay

    private var overlaySection: some View {
        Section(tr("Overlay")) {
            Picker(tr("Position"), selection: $settings.overlayPlacement) {
                ForEach(OverlayPlacement.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Button(tr("Show preview")) {
                    appState.overlay.present(.info(tr("The translation will appear here. Drag this window to place it anywhere.")),
                                             near: settings.captureRegion, autoHide: 10)
                }
                Text(tr("Drag the overlay by its background to move it; it then remembers that spot."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(tr("Auto-hide"))
                Slider(value: $settings.overlayAutoHideSeconds, in: 0...30, step: 1)
                Text(settings.overlayAutoHideSeconds == 0 ? tr("never") : tr("%d s", Int(settings.overlayAutoHideSeconds)))
                    .frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text(tr("Text size"))
                Slider(value: $settings.overlayFontSize, in: 12...26, step: 1)
                Text("\(Int(settings.overlayFontSize))").frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text(tr("Width"))
                Slider(value: $settings.overlayWidth, in: 380...900, step: 20)
                Text("\(Int(settings.overlayWidth))").frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: Learning

    private var learningSection: some View {
        Section(tr("Learning")) {
            HStack {
                Text(tr("Word difficulty threshold"))
                Slider(value: $settings.minimumDifficulty, in: 0.2...0.9, step: 0.05)
                Text(String(format: "%.2f", settings.minimumDifficulty)).frame(width: 50, alignment: .trailing)
            }
            Stepper(tr("Max suggestions: %d", settings.maxCandidates), value: $settings.maxCandidates, in: 1...12)
            Toggle(tr("Detect unknown phrasal verbs"), isOn: $settings.detectGenericPhrasalVerbs)
            Toggle(tr("Detect speaker name above the dialogue"), isOn: $settings.detectSpeakerLabel)
        }
    }

    // MARK: Hotkeys

    private var hotkeySection: some View {
        Section(tr("Hotkeys")) {
            HotkeyPicker(settings: settings)
            Text(tr("Current: %@. Works while the game is focused; the key press is not passed to the game.", settings.hotkeyDescription))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Privacy / Advanced

    private var privacySection: some View {
        Section(tr("Privacy")) {
            Text(tr("Screenshots are processed in memory and never saved. Only the recognized text is sent to a translation provider, and only if you choose a cloud provider. Vocabulary and history stay on this Mac. API keys are stored in the macOS Keychain."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        Section(tr("Advanced")) {
            TextField(tr("Local server URL"), text: $settings.libreTranslateURL)
            TextField(tr("OpenAI model"), text: $settings.openAIModel)
        }
    }
}
