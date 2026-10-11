import SwiftUI

/// Фирменные цвета, шрифт и логотип Recorgi.
/// Цвета и логотип лежат в Assets.xcassets, шрифт — в Fonts/Unbounded-Bold.ttf.
enum RecorgiBrand {
    // Цвета (в каталоге ассетов есть светлый и тёмный варианты)
    static let ink = Color("BrandInk")
    static let blue = Color("BrandBlue")
    static let blueTop = Color("BrandBlueTop")
    static let blueBottom = Color("BrandBlueBottom")
    static let corgiOrange = Color("CorgiOrange")
    static let corgiEar = Color("CorgiEar")
    static let recRed = Color("RecRed")

    /// Градиент фона иконки: сверху вниз.
    static let iconGradient = LinearGradient(
        colors: [blueTop, blue, blueBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Заголовочный шрифт логотипа — Unbounded Bold.
    /// PostScript-имя шрифта: "Unbounded-Bold".
    static func display(_ size: CGFloat) -> Font {
        .custom("Unbounded-Bold", size: size)
    }
}

/// Логотип «Recorgi» с кнопкой записи вместо буквы «o».
/// Векторный, сам переключается между светлой и тёмной темой.
struct RecorgiWordmark: View {
    var height: CGFloat = 28

    var body: some View {
        Image("Wordmark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Recorgi")
    }
}

#Preview {
    VStack(spacing: 24) {
        RecorgiWordmark(height: 48)
        Text("Запись экрана")
            .font(RecorgiBrand.display(22))
            .foregroundStyle(RecorgiBrand.ink)
    }
    .padding(40)
}
