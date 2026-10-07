import PencilKit
import SwiftUI

/// 写真への落書き。PencilKit のペン・マーカー・消しゴム・色えらび（下の道具パレット）で写真の上に描き、
/// 「アルバムに追加」で、写真と落書きを重ねた 1 枚を新しい写真として共有アルバムに入れる（元の写真はそのまま）
struct DoodleEditor: View {
    let image: UIImage
    /// 重ねた画像を受け取る
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    /// 置いたスタンプ（絵文字・場所・大きさ）
    @State private var stamps: [(emoji: String, center: CGPoint, size: CGFloat)] = []

    private static let choices = ["❤️", "⭐️", "✨", "😂", "😍", "🎉", "🔥", "👑"]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let size = fittedSize(in: geo.size)
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                    CanvasRepresentable(canvas: canvas)
                        .frame(width: size.width, height: size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .top) { stampBar }
            .navigationTitle("落書き")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("アルバムに追加") {
                        onSave(composite())
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    /// スタンプ：押すと写真のまんなかに大きく置く（あとは指で消したり描き足したり）
    private var stampBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    canvas.undoManager?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                ForEach(Self.choices, id: \.self) { emoji in
                    Button {
                        placeStamp(emoji)
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.black)
    }

    private func fittedSize(in area: CGSize) -> CGSize {
        let ratio = image.size.width / max(image.size.height, 1)
        let width = min(area.width, area.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    /// スタンプは絵文字を落書きの下に重ねて置く（少しずつずらして並べる）
    private func placeStamp(_ emoji: String) {
        let bounds = canvas.bounds
        let offset = CGFloat(stamps.count % 5) * 24
        stamps.append((emoji: emoji, center: CGPoint(x: bounds.midX + offset - 48, y: bounds.midY + offset - 48),
                       size: bounds.width * 0.28))
        refreshStampLayer()
    }

    private func refreshStampLayer() {
        canvas.subviews.filter { $0.tag == 4242 }.forEach { $0.removeFromSuperview() }
        for item in stamps {
            let label = UILabel()
            label.tag = 4242
            label.text = item.emoji
            label.font = .systemFont(ofSize: item.size)
            label.sizeToFit()
            label.center = item.center
            label.isUserInteractionEnabled = false
            canvas.insertSubview(label, at: 0)
        }
    }

    /// 元の写真の大きさで、写真・スタンプ・落書きを 1 枚に重ねる
    private func composite() -> UIImage {
        let bounds = canvas.bounds
        let scale = image.size.width / max(bounds.width, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            for item in stamps {
                let text = item.emoji as NSString
                let font = UIFont.systemFont(ofSize: item.size * scale)
                let size = text.size(withAttributes: [.font: font])
                text.draw(at: CGPoint(x: item.center.x * scale - size.width / 2, y: item.center.y * scale - size.height / 2),
                          withAttributes: [.font: font])
            }
            canvas.drawing.image(from: bounds, scale: scale)
                .draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

/// PencilKit の描くところ。表示されたら道具パレットを出す
private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.marker, color: .systemPink, width: 18)
        let picker = context.coordinator.picker
        picker.addObserver(canvas)
        DispatchQueue.main.async {
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let picker = PKToolPicker()
    }
}
