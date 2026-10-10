import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

struct PermissionsBanner: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Нужен доступ к записи экрана и микрофону")
                .font(.headline)
            Text("Открой Настройки системы, разреши Recorgi доступ, затем перезапусти приложение.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Открыть Настройки системы") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}
