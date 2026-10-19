import SwiftUI

/// First-launch wizard. Also reachable later via Settings → Run Setup Again.
struct OnboardingView: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionManager
    let onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, interfaceLanguage, languages, provider, apiKey, permission, gameWindow, captureArea, hotkey, anki, complete
    }

    @State private var step: Step = .welcome
    @State private var ankiState = StatusMonitor.Item.unknown
    @State private var checkingAnki = false
    @State private var pickedWindow: UInt32?

    /// The API-key step only exists for cloud providers.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .apiKey || settings.translationProvider.apiProvider != nil }
    }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(index + 1), total: Double(steps.count))
                .progressViewStyle(.linear)
                .padding(.horizontal, 28).padding(.top, 20)

            content
                .padding(.horizontal, 36).padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                if !isFirst { Button(tr("Back")) { go(-1) } }
                Spacer()
                if step == .welcome {
                    Button(tr("Get Started")) { go(1) }.keyboardShortcut(.defaultAction)
                } else if isLast {
                    Button(tr("Start Using App")) { finish() }.keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("Continue")) { go(1) }.keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 720, height: 600)
        .onAppear {
            // The recommended provider is DeepL; without a key the app still works via the free providers.
            if !settings.hasCompletedOnboarding && settings.translationProvider == .automatic {
                settings.translationProvider = .deepl
            }
        }
    }

    private func go(_ delta: Int) {
        let target = min(max(index + delta, 0), steps.count - 1)
        step = steps[target]
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .interfaceLanguage: interfaceLanguage
        case .languages: languages
        case .provider: provider
        case .apiKey: apiKey
        case .permission: permission
        case .gameWindow: gameWindow
        case .captureArea: captureArea
        case .hotkey: hotkey
        case .anki: anki
        case .complete: complete
        }
    }

    private func header(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 10)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            Text("Retrasmetter").font(.largeTitle.bold())
            Text(tr("Translate games. Learn from every dialogue.")).font(.title3).foregroundStyle(.secondary)
            Picker(tr("Interface language"), selection: $settings.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var interfaceLanguage: some View {
        VStack(alignment: .leading) {
            header(tr("Interface language"), tr("Choose the language of this app’s menus and buttons. You can change it later in Settings."))
            ForEach(InterfaceLanguage.allCases) { language in
                choiceRow(title: language.title, subtitle: nil, selected: settings.interfaceLanguage == language) {
                    settings.interfaceLanguage = language
                }
            }
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Languages"), tr("Which language is the game in, and what should it be translated into?"))
            Picker(tr("Language in the game"), selection: $settings.sourceLanguage) {
                ForEach(Language.all) { Text($0.displayName).tag($0) }
            }
            Picker(tr("Translate Into"), selection: $settings.targetLanguage) {
                ForEach(Language.all) { Text($0.displayName).tag($0) }
            }
            Text(tr("More languages can be added later."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(tr("Translation provider"),
                   tr("Text recognition always runs locally on your Mac. Only the recognized text is sent to a translation provider, and only if you choose a cloud one."))
            choiceRow(title: "DeepL  ·  " + tr("Recommended"),
                      subtitle: tr("Free API plan available. Suitable for game dialogue translation."),
                      selected: settings.translationProvider == .deepl) { settings.translationProvider = .deepl }
            choiceRow(title: "OpenAI",
                      subtitle: tr("Optional AI translation and language explanations. Usage may cost money."),
                      selected: settings.translationProvider == .openai) { settings.translationProvider = .openai }
            choiceRow(title: tr("Apple Translation / local"),
                      subtitle: tr("Free and offline. Uses Apple Translation (macOS 15+) or a local LibreTranslate server."),
                      selected: settings.translationProvider == .automatic) { settings.translationProvider = .automatic }
        }
    }

    @ViewBuilder
    private var apiKey: some View {
        if let api = settings.translationProvider.apiProvider {
            VStack(alignment: .leading, spacing: 12) {
                header(api.keyFieldTitle,
                       api == .openai
                       ? tr("A ChatGPT subscription and API billing are separate. Paste a key from your OpenAI Platform account.")
                       : tr("Paste your DeepL authentication key. The key is stored in the macOS Keychain."))
                ProviderKeyEditor(provider: api, settings: settings)
                    .id(api)
                Text(tr("You can skip this step; without a key the app uses the free providers. Add the key later in Settings → Translation."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Screen Recording"),
                   tr("Retrasmetter needs Screen Recording permission to read dialogue displayed by games. It only watches the dialogue area you select, and never saves screenshots."))
            StatusLabel(item: permissions.hasScreenRecordingAccess
                        ? .init(level: .ok, text: tr("Permission granted"))
                        : .init(level: .warning, text: tr("Permission required")))
                .font(.title3)
            if !permissions.hasScreenRecordingAccess {
                HStack {
                    Button(tr("Grant Permission")) { _ = permissions.requestAccess() }
                    Button(tr("Open System Settings")) { permissions.openSystemSettings() }
                }
                Text(tr("After enabling the permission in System Settings, quit and reopen this app (macOS applies the change after a relaunch)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { permissions.refresh() }
    }

    private var gameWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Game Window"), tr("Open the game, then pick its window. The dialogue area will follow the window if you move it."))
            WindowPickerView(selectedID: $pickedWindow) { window in
                let profile = appState.profiles.activeProfile
                    ?? appState.profiles.createProfile(name: window.appName)
                appState.profiles.attach(window: window, to: profile.id)
            }
        }
    }

    private var captureArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Dialogue Area"), tr("Select the area where game dialogue usually appears."))
            HStack {
                Button(tr("Select Area")) { appState.selectCaptureArea() }
                if let region = settings.captureRegion {
                    StatusLabel(item: .init(level: .ok, text: tr("Dialogue area configured")))
                    Text(region.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            OCRTestPanel(appState: appState, settings: settings)
        }
    }

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Hotkey"), tr("Press this shortcut in the game to start Reading Mode, then click any word. Press it again or Esc to exit."))
            HotkeyPicker(settings: settings).frame(maxWidth: 360)
            HStack {
                Text(tr("Reading Mode:")).foregroundStyle(.secondary)
                Text(settings.hotkeyDescription)
                    .font(.system(.title2, design: .rounded).bold())
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var anki: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tr("Connect Anki?"), tr("Anki integration is optional. It uses the AnkiConnect add-on on this Mac."))
            HStack {
                choiceRow(title: tr("Connect now"), subtitle: nil, selected: settings.ankiEnabled) {
                    settings.ankiEnabled = true
                    Task { await checkAnki() }
                }
                choiceRow(title: tr("Skip"), subtitle: nil, selected: !settings.ankiEnabled) {
                    settings.ankiEnabled = false
                }
            }
            if settings.ankiEnabled {
                HStack {
                    StatusLabel(item: ankiState)
                    if checkingAnki { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(tr("Check again")) { Task { await checkAnki() } }
                }
                Text(tr("Install the AnkiConnect add-on (code 2055492159) and keep Anki running. You can choose the deck later in Settings."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { if settings.ankiEnabled { await checkAnki() } }
    }

    private func checkAnki() async {
        checkingAnki = true
        let service = AnkiConnectService(urlString: settings.ankiURL)
        let available = await service?.isAvailable() ?? false
        ankiState = available
            ? .init(level: .ok, text: tr("Anki detected"))
            : .init(level: .warning, text: tr("Anki not detected"))
        checkingAnki = false
    }

    private var complete: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text(tr("You’re ready.")).font(.largeTitle.bold())
            Text(tr("Open your game and press %@ to translate the dialogue.", settings.hotkeyDescription))
                .foregroundStyle(.secondary)
            Button(tr("Try Translation")) { appState.translateCurrentDialogue(fromMenu: false) }
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shared row

    private func choiceRow(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
