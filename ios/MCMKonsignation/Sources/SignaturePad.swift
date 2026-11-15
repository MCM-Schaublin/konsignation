import SwiftUI
import UIKit

/// Freihand-Unterschrift mit Finger oder Stift. Striche werden relativ zur Feldgröße (0…1) gespeichert,
/// damit sie beim Export auf jede Größe passen.
struct SignatureCanvas: View {
    @Binding var strokes: [[CGPoint]]
    @State private var current: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for stroke in strokes + [current] where stroke.count > 1 {
                    var path = Path()
                    path.move(to: scaled(stroke[0], size))
                    for p in stroke.dropFirst() {
                        path.addLine(to: scaled(p, size))
                    }
                    ctx.stroke(path, with: .color(.black),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = CGPoint(x: value.location.x / geo.size.width,
                                        y: value.location.y / geo.size.height)
                        current.append(p)
                    }
                    .onEnded { _ in
                        if current.count > 1 { strokes.append(current) }
                        current = []
                    }
            )
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
    }

    private func scaled(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}

/// Erzeugt aus den Strichen ein PNG für das PDF.
enum SignatureRender {
    static func image(_ strokes: [[CGPoint]], width: CGFloat = 700, height: CGFloat = 200) -> UIImage? {
        guard !strokes.isEmpty else { return nil }
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let c = ctx.cgContext
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(5)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            for stroke in strokes where stroke.count > 1 {
                c.beginPath()
                c.move(to: CGPoint(x: stroke[0].x * width, y: stroke[0].y * height))
                for p in stroke.dropFirst() {
                    c.addLine(to: CGPoint(x: p.x * width, y: p.y * height))
                }
                c.strokePath()
            }
        }
    }
}
