import SwiftUI

/// A brief animated brand moment shown over the main window right after
/// launch — a hand-drawn (in SwiftUI shapes, not the static app icon) take
/// on the corgi mascot that actually performs: ears perk up and wiggle,
/// eyes blink, tongue flicks out happily, nose pulses like a recording
/// dot — before the whole thing fades away to reveal the real UI (see
/// ContentView, which owns the show/hide timing).
///
/// Built from plain shapes instead of referencing the static AppIcon
/// image because the parts need to animate independently — there's no
/// multi-layer source art for that, and the AppIcon/menu-bar assets are
/// all flattened into one silhouette. Visual language still matches them
/// (rounded everything, the same brand colors), just redrawn as
/// composable pieces.
///
/// Deliberately NOT accent-tinted, unlike CLAUDE.md's "every new UI
/// element follows the chosen theme" rule: this is static brand identity,
/// the same reason the app icon itself doesn't retint to the user's
/// accent color either. BrandBlueTop/Bottom only define a single
/// (universal) value each for exactly this reason — this backdrop stays
/// the same regardless of light/dark mode too, matching the app icon's
/// own fixed look.
struct SplashView: View {
    // Face entrance.
    @State private var faceScale: CGFloat = 0.4
    @State private var faceOpacity: Double = 0

    // Ears start laid flat/small, then perk up into their resting
    // (diamond) rotation, then do a couple of quick happy wiggles.
    @State private var leftEarRotation = Angle(degrees: 10)
    @State private var leftEarScale: CGFloat = 0.5
    @State private var rightEarRotation = Angle(degrees: -10)
    @State private var rightEarScale: CGFloat = 0.5
    private let earRestRotation = 45.0

    // A single blink partway through.
    @State private var eyeScaleY: CGFloat = 1

    // A happy tongue flick — grown via an explicit height (not
    // scaleEffect(anchor:)), with the offset recomputed from that same
    // height every frame, so the top edge is mathematically pinned at
    // tongueTopY instead of relying on an anchor behaving the way you'd
    // expect. scaleEffect's anchor was readable as "unrolling downward"
    // in theory, but visually read as dropping in from above the mascot
    // instead of from under the nose — this can't drift the same way.
    @State private var tongueHeight: CGFloat = 0
    @State private var tongueOpacity: Double = 0
    private let tongueTopY: CGFloat = 50
    private let tongueFullHeight: CGFloat = 24

    // Nose "recording" pulse ring — a one-time expand-and-fade, not a
    // continuous loop, so it reads as a flourish rather than ambient noise.
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0

    @State private var wordmarkOffset: CGFloat = 16
    @State private var wordmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("BrandBlueTop"), Color("BrandBlueBottom")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                mascot
                Text("Recorgi")
                    .font(.custom("Unbounded-Bold", size: 30))
                    .foregroundStyle(.white)
                    .offset(y: wordmarkOffset)
                    .opacity(wordmarkOpacity)
            }
        }
        .onAppear { animate() }
    }

    private var mascot: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 3)
                .frame(width: 150, height: 150)
                .scaleEffect(pulseScale)

            // Ears: a rounded rectangle rotated 45° into a kite/diamond,
            // its lower half tucked behind the face circle below — a
            // common flat-mascot trick for a soft pointed ear without
            // hand-tuned curves. Slightly taller than wide (not a square)
            // reads less like a geometric diamond, closer to an actual ear
            // silhouette. Each one animates its own rotation/scale so they
            // can perk up independently; the lighter inset on top is the
            // two-tone inner ear real corgis have.
            ear.rotationEffect(leftEarRotation).scaleEffect(leftEarScale).offset(x: -36, y: -48)
            ear.rotationEffect(rightEarRotation).scaleEffect(rightEarScale).offset(x: 36, y: -48)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color("CorgiOrange").mix(with: .white, by: 0.3), Color("CorgiOrange")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 124, height: 124)

            Ellipse()
                .fill(Color.white)
                // Top edge unchanged from before (-19 to -19, same offset
                // - half-height), just stretched further down so the
                // mouth (bottom edge at y:51, plus a little extra from
                // its stroke width and rounded line caps) sits safely
                // inside instead of poking past the white.
                .frame(width: 44, height: 78)
                .offset(y: 20)
                // A whisper of shadow where the snout meets the face,
                // instead of a flat sticker-like patch with a hard edge.
                .shadow(color: Color("CorgiEar").opacity(0.35), radius: 2, y: 1)

            // Cheek blush — soft, low-opacity, just enough to round out
            // the face instead of leaving it a flat single-tone disc.
            cheekBlush.offset(x: -40, y: 20)
            cheekBlush.offset(x: 40, y: 20)

            HStack(spacing: 30) {
                eye
                eye
            }
            .offset(y: -8)

            smile

            // Tongue BEHIND the nose in z-order, so its top edge tucks out
            // of sight under the nose instead of floating as a separate
            // red shape below it. Flat-ish top / rounded tip
            // (UnevenRoundedRectangle, not a uniform RoundedRectangle) so
            // it reads as a tongue tip, not a generic pill. The offset is
            // tongueTopY + half of the current height, so as tongueHeight
            // grows from 0 the shape's center moves down to match — the
            // top edge (tongueTopY) itself never moves.
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 9,
                topTrailingRadius: 3,
                style: .continuous
            )
            .fill(Color("RecRed").opacity(0.8))
            .frame(width: 16, height: tongueHeight)
            .offset(y: tongueTopY + tongueHeight / 2)
            .opacity(tongueOpacity)

            nose
        }
        .scaleEffect(faceScale)
        .opacity(faceOpacity)
        // An explicit frame, generous enough to contain every offset piece
        // (ears, tongue, cheeks) and the pulse ring at its widest — without
        // it, drawingGroup below sizes its offscreen render buffer from the
        // *unoffset* layout size of its content, which clipped anything
        // positioned away from center to a visibly smaller square. This is
        // what the pulse ring's own stroke-circle frame (150×150) was
        // accidentally doing duty as before, too small once the ring
        // animates out past it.
        .frame(width: 210, height: 210)
        // Flattens the whole composite into one offscreen render pass —
        // without this, the overlapping shapes (especially the rotating
        // ears) showed visible seams/stairstepping where one shape's own
        // antialiased edge met another's, instead of blending smoothly as
        // one picture.
        .drawingGroup()
        .shadow(color: Color("BrandBlueBottom").opacity(0.45), radius: 18, y: 10)
    }

    private var ear: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color("CorgiEar"))
                .frame(width: 52, height: 64)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .frame(width: 26, height: 40)
                .offset(y: 6)
        }
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 13, height: 13)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 3.5, height: 3.5)
                .offset(x: -2.5, y: -2.5)
        }
        .scaleEffect(x: 1, y: eyeScaleY)
    }

    private var cheekBlush: some View {
        Circle()
            .fill(Color("RecRed").opacity(0.18))
            .frame(width: 22, height: 14)
            .blur(radius: 3)
    }

    // Nose above, mouth below — the actual order a snout reads in: the
    // nose sits at eye level on the muzzle, the mouth line starts right
    // under it and curves down/out. Was accidentally reversed before.
    private var smile: some View {
        SmileShape()
            .stroke(Color("CorgiEar").opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 30, height: 10)
            .offset(y: 46)
    }

    private var nose: some View {
        ZStack {
            Circle()
                .fill(Color("RecRed"))
                .frame(width: 34, height: 34)
            Ellipse()
                .fill(Color.white.opacity(0.5))
                .frame(width: 12, height: 7)
                .offset(x: -5, y: -7)
        }
        .offset(y: 24)
    }

    private func animate() {
        Task { @MainActor in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                faceScale = 1
                faceOpacity = 1
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                leftEarRotation = .degrees(earRestRotation)
                leftEarScale = 1
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.08)) {
                rightEarRotation = .degrees(earRestRotation)
                rightEarScale = 1
            }
            pulseScale = 1
            pulseOpacity = 0.6
            withAnimation(.easeOut(duration: 0.9)) {
                pulseScale = 1.3
                pulseOpacity = 0
            }

            try? await Task.sleep(for: .seconds(0.5))
            // A couple of quick happy wiggles once the ears have perked up.
            withAnimation(.easeInOut(duration: 0.12)) {
                leftEarRotation = .degrees(earRestRotation - 8)
                rightEarRotation = .degrees(earRestRotation + 8)
            }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeInOut(duration: 0.12)) {
                leftEarRotation = .degrees(earRestRotation + 6)
                rightEarRotation = .degrees(earRestRotation - 6)
            }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeInOut(duration: 0.14)) {
                leftEarRotation = .degrees(earRestRotation)
                rightEarRotation = .degrees(earRestRotation)
            }

            withAnimation(.easeOut(duration: 0.45)) {
                wordmarkOffset = 0
                wordmarkOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.easeInOut(duration: 0.1)) { eyeScaleY = 0.1 }
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation(.easeInOut(duration: 0.12)) { eyeScaleY = 1 }

            try? await Task.sleep(for: .seconds(0.15))
            // Gentle, not bouncy: dampingFraction close to 1 keeps this a
            // smooth "flick out" rather than overshooting past full length
            // and springing back.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                tongueHeight = tongueFullHeight
                tongueOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeInOut(duration: 0.25)) {
                tongueHeight = 0
                tongueOpacity = 0
            }
        }
    }
}

/// A shallow two-lobe smile, drawn as two quadratic curves meeting at the
/// top center — stroked, not filled, so it reads as a mouth line rather
/// than another solid shape.
private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        path.move(to: top)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35),
            control: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY)
        )
        path.move(to: top)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35),
            control: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.maxY)
        )
        return path
    }
}
