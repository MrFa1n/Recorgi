import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

struct PermissionsBanner: View {
    @ObservedObject var permissions: PermissionsManager

    private var needsScreenRecording: Bool { permissions.screenRecordingStatus != .granted }
    private var needsMicrophone: Bool { permissions.microphoneStatus == .denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нужен доступ")
                .font(.headline)

            if needsScreenRecording {
                statusLine(
                    "Запись экрана",
                    detail: "После включения в Настройках нужно полностью закрыть и снова открыть Recorgi (⌘Q, не просто переключить окно) — так требует macOS.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
            }

            if needsMicrophone {
                statusLine(
                    "Микрофон",
                    detail: "Включи доступ в Настройках — применяется сразу, без перезапуска.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
            }

            Button("Проверить снова") {
                permissions.refresh()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusLine(_ title: String, detail: String, settingsURL: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).bold()
                Spacer()
                Button("Открыть Настройки") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
