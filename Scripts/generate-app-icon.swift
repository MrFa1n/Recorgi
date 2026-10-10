#!/usr/bin/env swift
// Renders the Recorgi app icon (a corgi face + a "record" dot) to a
// 1024x1024 PNG using SwiftUI's ImageRenderer. Re-run after tweaking the
// shapes below, then regenerate the iconset:
//
//   swift Scripts/generate-app-icon.swift /tmp/icon-1024.png
//   sips -z 16 16 /tmp/icon-1024.png --out Recorgi/Assets.xcassets/AppIcon.appiconset/icon_16x16.png
//   ...(repeat per size listed in AppIcon.appiconset/Contents.json)...
//   cp /tmp/icon-1024.png Recorgi/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png

import SwiftUI
import AppKit

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Corgi facial blaze: a rounded white patch covering the muzzle/cheeks/chin.
struct Blaze: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.62),
            control1: CGPoint(x: w * 0.18, y: h * 0.10),
            control2: CGPoint(x: 0, y: h * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: 0, y: h * 0.86),
            control2: CGPoint(x: w * 0.22, y: h)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.62),
            control1: CGPoint(x: w * 0.78, y: h),
            control2: CGPoint(x: w, y: h * 0.86)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w, y: h * 0.30),
            control2: CGPoint(x: w * 0.82, y: h * 0.10)
        )
        path.closeSubpath()
        return path
    }
}

struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 0.22, y: h * 1.6))
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.78, y: h * 1.6))
        return path
    }
}

struct CorgiIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.86, blue: 0.62), Color(red: 1.0, green: 0.73, blue: 0.38)],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                let s = geo.size.width

                ZStack {
                    Triangle()
                        .fill(Color(red: 0.88, green: 0.52, blue: 0.20))
                        .frame(width: s * 0.30, height: s * 0.34)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -s * 0.235, y: -s * 0.27)
                    Triangle()
                        .fill(Color(red: 0.88, green: 0.52, blue: 0.20))
                        .frame(width: s * 0.30, height: s * 0.34)
                        .rotationEffect(.degrees(18))
                        .offset(x: s * 0.235, y: -s * 0.27)

                    Triangle()
                        .fill(Color(red: 0.98, green: 0.80, blue: 0.70))
                        .frame(width: s * 0.14, height: s * 0.20)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -s * 0.225, y: -s * 0.24)
                    Triangle()
                        .fill(Color(red: 0.98, green: 0.80, blue: 0.70))
                        .frame(width: s * 0.14, height: s * 0.20)
                        .rotationEffect(.degrees(18))
                        .offset(x: s * 0.225, y: -s * 0.24)

                    Ellipse()
                        .fill(Color(red: 0.91, green: 0.58, blue: 0.24))
                        .frame(width: s * 0.62, height: s * 0.56)
                        .offset(y: s * 0.02)

                    Blaze()
                        .fill(Color.white)
                        .frame(width: s * 0.46, height: s * 0.40)
                        .offset(y: s * 0.145)

                    Circle().fill(Color.black)
                        .frame(width: s * 0.05, height: s * 0.05)
                        .offset(x: -s * 0.115, y: -s * 0.01)
                    Circle().fill(Color.black)
                        .frame(width: s * 0.05, height: s * 0.05)
                        .offset(x: s * 0.115, y: -s * 0.01)
                    Circle().fill(Color.white.opacity(0.85))
                        .frame(width: s * 0.015, height: s * 0.015)
                        .offset(x: -s * 0.124, y: -s * 0.02)
                    Circle().fill(Color.white.opacity(0.85))
                        .frame(width: s * 0.015, height: s * 0.015)
                        .offset(x: s * 0.106, y: -s * 0.02)

                    RoundedRectangle(cornerRadius: s * 0.018)
                        .fill(Color.black)
                        .frame(width: s * 0.046, height: s * 0.030)
                        .offset(y: s * 0.085)

                    Smile()
                        .stroke(Color.black.opacity(0.65), style: StrokeStyle(lineWidth: s * 0.009, lineCap: .round))
                        .frame(width: s * 0.09, height: s * 0.028)
                        .offset(y: s * 0.145)

                    Circle().fill(Color(red: 1.0, green: 0.60, blue: 0.52).opacity(0.5))
                        .frame(width: s * 0.065, height: s * 0.065)
                        .offset(x: -s * 0.185, y: s * 0.10)
                    Circle().fill(Color(red: 1.0, green: 0.60, blue: 0.52).opacity(0.5))
                        .frame(width: s * 0.065, height: s * 0.065)
                        .offset(x: s * 0.185, y: s * 0.10)
                }
                .position(x: s * 0.5, y: s * 0.46)

                // Record badge, bottom-right — ties "record" into the mark.
                ZStack {
                    Circle().fill(Color.white).frame(width: s * 0.26, height: s * 0.26)
                    Circle().fill(Color(red: 0.95, green: 0.18, blue: 0.22)).frame(width: s * 0.20, height: s * 0.20)
                }
                .position(x: s * 0.815, y: s * 0.815)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: CorgiIcon())
    renderer.scale = 1
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render icon\n", stderr)
        exit(1)
    }

    let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
    do {
        try png.write(to: URL(fileURLWithPath: outputPath))
        print("Wrote \(outputPath)")
    } catch {
        fputs("Failed to write PNG: \(error)\n", stderr)
        exit(1)
    }
}
