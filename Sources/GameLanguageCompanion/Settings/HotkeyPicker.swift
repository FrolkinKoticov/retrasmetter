import SwiftUI

/// Modifier + letter picker shared by Settings and Onboarding.
struct HotkeyPicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack {
            Picker(tr("Modifier"), selection: $settings.hotkeyModifiers) {
                ForEach(HotkeyModifiers.allCases) { Text($0.symbols).tag($0) }
            }
            Picker(tr("Key"), selection: $settings.hotkeyKey) {
                ForEach(HotkeyKeys.letters, id: \.self) { Text($0).tag($0) }
            }
        }
    }
}
