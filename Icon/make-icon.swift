// Renders the Face Unlock app icon (1024px) with SwiftUI.
import AppKit
import SwiftUI

struct Corners: Shape {
    func path(in r: CGRect) -> Path {
        let l = r.width * 0.28, c = r.width * 0.16
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.minY + l)); p.addLine(to: .init(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: .init(x: r.minX + c, y: r.minY), control: .init(x: r.minX, y: r.minY)); p.addLine(to: .init(x: r.minX + l, y: r.minY))
        p.move(to: .init(x: r.maxX - l, y: r.minY)); p.addLine(to: .init(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: .init(x: r.maxX, y: r.minY + c), control: .init(x: r.maxX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY + l))
        p.move(to: .init(x: r.maxX, y: r.maxY - l)); p.addLine(to: .init(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: .init(x: r.maxX - c, y: r.maxY), control: .init(x: r.maxX, y: r.maxY)); p.addLine(to: .init(x: r.maxX - l, y: r.maxY))
        p.move(to: .init(x: r.minX + l, y: r.maxY)); p.addLine(to: .init(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: .init(x: r.minX, y: r.maxY - c), control: .init(x: r.minX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct Face: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width
        var p = Path()
        for x in [0.34, 0.66] {
            p.move(to: .init(x: r.minX + w * x, y: r.minY + w * 0.34)); p.addLine(to: .init(x: r.minX + w * x, y: r.minY + w * 0.43))
        }
        p.move(to: .init(x: r.minX + w * 0.5, y: r.minY + w * 0.34)); p.addLine(to: .init(x: r.minX + w * 0.5, y: r.minY + w * 0.56))
        p.addLine(to: .init(x: r.minX + w * 0.44, y: r.minY + w * 0.56))
        p.move(to: .init(x: r.minX + w * 0.34, y: r.minY + w * 0.67))
        p.addQuadCurve(to: .init(x: r.minX + w * 0.66, y: r.minY + w * 0.67), control: .init(x: r.minX + w * 0.5, y: r.minY + w * 0.8))
        return p
    }
}

struct Icon: View {
    let green = Color(red: 0.36, green: 0.95, blue: 0.45)
    var body: some View {
        ZStack {
            // macOS icon body: 824pt squircle on a 1024 canvas
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 12)

            Group {
                Corners().stroke(green, style: StrokeStyle(lineWidth: 34, lineCap: .round))
                Face().stroke(green, style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 440, height: 440)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Icon())
    r.scale = 1
    let data = NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "icon-1024.png"))
}
MainActor.assumeIsolated { render() }
