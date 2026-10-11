import PencilKit
import SwiftUI

/// 写真への落書き。2 つのモードを切り替えて使う：
/// - ペン：PencilKit のペン・マーカー・消しゴム・色えらび（下の道具パレット）で写真の上に描く
/// - ステッカー：上の列から選んで貼る。指で動かす、2 本指で大きさと向きを変える、2 回タップで文字を書き換える
///   （ボックスロゴ風・HELLO my name is・CAUTION・日付・ふきだし・マスキングテープ・絵文字）
/// 「保存」で、写真・落書き・ステッカーを重ねた 1 枚で写真を上書きする（元の写真は iCloud に取っておき、「元に戻す」で戻せる）
struct DoodleEditor: View {
    let image: UIImage
    /// 重ねた画像を受け取る
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var mode: Mode = .pen
    @State private var stickers: [Sticker] = []
    @State private var selected: UUID?
    @State private var dragStart: CGPoint?
    @State private var pinchBase: (scale: CGFloat, angle: Angle)?
    /// 文字を入れる（新しく貼るとき・書き換えるとき）
    @State private var textEntry: TextEntry?
    @State private var entryText = ""

    enum Mode { case pen, sticker }

    private struct TextEntry {
        /// 新しく貼る種類（書き換えのときは nil）
        var newKind: Sticker.Kind?
        var editing: UUID?
    }

    private static let emojis = ["❤️", "⭐️", "✨", "😂", "😍", "🥹", "😎", "🎉", "🔥", "👑", "💯", "🌸",
                                 "🍓", "🐶", "🐱", "👍", "✌️", "💋", "🌈", "☀️", "🌙", "📸", "🎂", "🍻"]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let size = fittedSize(in: geo.size)
                ZStack {
                    Color.black.ignoresSafeArea()
                        .onTapGesture { selected = nil }
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                        CanvasRepresentable(canvas: canvas, drawing: mode == .pen)
                            .allowsHitTesting(mode == .pen)
                        stickerLayer(canvasWidth: size.width)
                            .allowsHitTesting(mode == .sticker)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .top) { topBar }
            .navigationTitle("落書き")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        selected = nil
                        onSave(composite())
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .alert(textEntry?.newKind == nil ? "文字を書き換える" : "文字を入れる",
                   isPresented: Binding(get: { textEntry != nil }, set: { if !$0 { textEntry = nil } })) {
                TextField("文字", text: $entryText)
                Button("OK") { commitText() }
                Button("キャンセル", role: .cancel) { textEntry = nil }
            }
        }
    }

    // MARK: 上の列（モード・元に戻す・ステッカー）

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Picker("モード", selection: $mode) {
                    Label("ペン", systemImage: "pencil.tip").tag(Mode.pen)
                    Label("ステッカー", systemImage: "star.square.on.square").tag(Mode.sticker)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Spacer()
                if let selected, mode == .sticker {
                    Button {
                        stickers.removeAll { $0.id == selected }
                        self.selected = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("選んだステッカーを消す")
                }
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("元に戻す")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            if mode == .sticker {
                stickerTray
            }
        }
        .padding(.vertical, 6)
        .background(Color.black)
        .onChange(of: mode) { _, newMode in
            if newMode == .pen { selected = nil }
        }
    }

    private var stickerTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Sticker.Kind.textKinds, id: \.self) { kind in
                    Button {
                        entryText = kind.defaultText
                        textEntry = TextEntry(newKind: kind)
                    } label: {
                        StickerView(sticker: Sticker(kind: kind, text: kind.sampleText), base: 64)
                            .frame(width: 76, height: 48)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12)))
                    }
                    .accessibilityLabel(kind.name)
                }
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        add(Sticker(kind: .emoji, text: emoji))
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12)))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: ステッカーの層

    private func stickerLayer(canvasWidth: CGFloat) -> some View {
        let base = canvasWidth * 0.42
        return ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }
            ForEach(stickers) { sticker in
                let isSelected = sticker.id == selected
                StickerView(sticker: sticker, base: base)
                    .overlay {
                        if isSelected {
                            Rectangle()
                                .stroke(.white, style: StrokeStyle(lineWidth: 1.5 / sticker.scale,
                                                                   dash: [6 / sticker.scale]))
                                .padding(-8)
                                .shadow(radius: 2)
                        }
                    }
                    .scaleEffect(sticker.scale)
                    .rotationEffect(sticker.angle)
                    // 触れる場所はステッカーの上だけ（position より前に付ける）
                    .onTapGesture(count: 2) { edit(sticker) }
                    .onTapGesture { selected = sticker.id }
                    .gesture(dragGesture(for: sticker.id))
                    .position(sticker.center)
            }
        }
        // 2 本指：選んでいるステッカーの大きさと向きを変える（ステッカーの外でつまんでもいい）
        .simultaneousGesture(
            MagnifyGesture().simultaneously(with: RotateGesture())
                .onChanged { value in
                    guard let id = selected, let index = stickers.firstIndex(where: { $0.id == id }) else { return }
                    if pinchBase == nil { pinchBase = (stickers[index].scale, stickers[index].angle) }
                    guard let base = pinchBase else { return }
                    if let magnify = value.first {
                        stickers[index].scale = min(max(base.scale * magnify.magnification, 0.2), 6)
                    }
                    if let rotate = value.second {
                        stickers[index].angle = base.angle + rotate.rotation
                    }
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    private func dragGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
                if dragStart == nil {
                    dragStart = stickers[index].center
                    selected = id
                }
                guard let start = dragStart else { return }
                stickers[index].center = CGPoint(x: start.x + value.translation.width,
                                                 y: start.y + value.translation.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: 操作

    private func add(_ sticker: Sticker) {
        var sticker = sticker
        let bounds = canvas.bounds
        // 少しずつずらして、写真のまんなかあたりに置く
        let offset = CGFloat(stickers.count % 5) * 18 - 36
        sticker.center = CGPoint(x: bounds.midX + offset, y: bounds.midY + offset)
        sticker.angle = sticker.kind.defaultAngle
        stickers.append(sticker)
        selected = sticker.id
        mode = .sticker
    }

    private func edit(_ sticker: Sticker) {
        guard sticker.kind != .emoji else { return }
        selected = sticker.id
        entryText = sticker.text
        textEntry = TextEntry(newKind: nil, editing: sticker.id)
    }

    private func commitText() {
        guard let entry = textEntry else { return }
        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        textEntry = nil
        guard !text.isEmpty else { return }
        if let kind = entry.newKind {
            add(Sticker(kind: kind, text: text))
        } else if let id = entry.editing, let index = stickers.firstIndex(where: { $0.id == id }) {
            stickers[index].text = text
        }
    }

    private func undo() {
        if mode == .sticker, !stickers.isEmpty {
            let last = stickers.removeLast()
            if selected == last.id { selected = nil }
        } else {
            canvas.undoManager?.undo()
        }
    }

    private func fittedSize(in area: CGSize) -> CGSize {
        let ratio = image.size.width / max(image.size.height, 1)
        let width = min(area.width, area.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    /// 元の写真の大きさで、写真・落書き・ステッカーを 1 枚に重ねる（ステッカーは落書きの上）
    @MainActor
    private func composite() -> UIImage {
        let bounds = canvas.bounds
        let scale = image.size.width / max(bounds.width, 1)
        var stickerImage: UIImage?
        if !stickers.isEmpty {
            let layer = ZStack {
                ForEach(stickers) { sticker in
                    StickerView(sticker: sticker, base: bounds.width * 0.42)
                        .scaleEffect(sticker.scale)
                        .rotationEffect(sticker.angle)
                        .position(sticker.center)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            let renderer = ImageRenderer(content: layer)
            renderer.scale = scale
            renderer.isOpaque = false
            stickerImage = renderer.uiImage
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: image.size)
            image.draw(in: rect)
            canvas.drawing.image(from: bounds, scale: scale).draw(in: rect)
            stickerImage?.draw(in: rect)
        }
    }
}

// MARK: - ステッカー

struct Sticker: Identifiable {
    enum Kind: Hashable {
        case emoji
        /// 赤い箱に白い斜めの太字（ストリートブランドのボックスロゴ風。文字は自分で入れる）
        case boxLogo
        /// 名札「HELLO my name is」
        case nameTag
        /// 黄色と黒の CAUTION テープ
        case caution
        /// フィルムカメラの日付（オレンジの数字）
        case dateStamp
        /// ふきだし
        case bubble
        /// マスキングテープに手書き
        case tape

        static let textKinds: [Kind] = [.boxLogo, .nameTag, .caution, .dateStamp, .bubble, .tape]

        var name: String {
            switch self {
            case .emoji: return "絵文字"
            case .boxLogo: return "ボックスロゴ"
            case .nameTag: return "HELLO my name is"
            case .caution: return "CAUTION テープ"
            case .dateStamp: return "日付"
            case .bubble: return "ふきだし"
            case .tape: return "マスキングテープ"
            }
        }

        /// 貼るときに最初に入っている文字
        var defaultText: String {
            switch self {
            case .emoji: return ""
            case .boxLogo: return "Film"
            case .nameTag: return "なまえ"
            case .caution: return "CAUTION"
            case .dateStamp: return Self.today
            case .bubble: return "やっほー！"
            case .tape: return "memories"
            }
        }

        /// 上の列の見本の文字
        var sampleText: String {
            switch self {
            case .nameTag: return "Me"
            case .bubble: return "Hi!"
            case .tape: return "memo"
            default: return defaultText
            }
        }

        var defaultAngle: Angle {
            switch self {
            case .nameTag: return .degrees(-6)
            case .caution: return .degrees(-12)
            case .tape: return .degrees(4)
            default: return .zero
            }
        }

        /// フィルムカメラの写し込みの日付の形（'26 10 11）
        private static var today: String {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return String(format: "'%02d %02d %02d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
        }
    }

    let id = UUID()
    var kind: Kind
    var text: String
    /// 落書きの面の中の位置
    var center: CGPoint = .zero
    var scale: CGFloat = 1
    var angle: Angle = .zero
}

/// ステッカー 1 枚の見た目。base は大きさのもと（写真の幅の 4 割ほど）
struct StickerView: View {
    let sticker: Sticker
    let base: CGFloat

    private static let red = Color(red: 0.88, green: 0.1, blue: 0.15)
    private static let yellow = Color(red: 1, green: 0.84, blue: 0.0)

    var body: some View {
        switch sticker.kind {
        case .emoji:
            Text(sticker.text)
                .font(.system(size: base * 0.55))

        case .boxLogo:
            Text(sticker.text)
                .font(.custom("Futura-Bold", size: base * 0.2))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                // 右に傾けた太字（Futura の太字には斜体がないので、ゆがめて作る）
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: base * 0.03, ty: 0))
                .padding(.horizontal, base * 0.07)
                .padding(.vertical, base * 0.025)
                .background(Self.red)

        case .nameTag:
            VStack(spacing: 0) {
                VStack(spacing: base * 0.005) {
                    Text("HELLO")
                        .font(.system(size: base * 0.17, weight: .black))
                    Text("my name is")
                        .font(.system(size: base * 0.065, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, base * 0.04)
                .frame(maxWidth: .infinity)
                .background(Self.red)
                Text(sticker.text)
                    .font(.custom("MarkerFelt-Wide", size: base * 0.17))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, base * 0.05)
                    .frame(maxWidth: .infinity, minHeight: base * 0.32)
                    .background(Color.white)
                Self.red.frame(height: base * 0.06)
            }
            .frame(width: base)
            .clipShape(RoundedRectangle(cornerRadius: base * 0.06, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: base * 0.02, y: base * 0.01)

        case .caution:
            Text(sticker.text)
                .font(.system(size: base * 0.11, weight: .black))
                .tracking(base * 0.01)
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, base * 0.12)
                .padding(.vertical, base * 0.06)
                .background(Self.yellow)
                .overlay(alignment: .top) { CautionStripes().frame(height: base * 0.035) }
                .overlay(alignment: .bottom) { CautionStripes().frame(height: base * 0.035) }

        case .dateStamp:
            Text(sticker.text)
                .font(.system(size: base * 0.13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.1))
                .lineLimit(1)
                .fixedSize()
                .shadow(color: Color(red: 1, green: 0.4, blue: 0).opacity(0.8), radius: base * 0.015)

        case .bubble:
            Text(sticker.text)
                .font(.system(size: base * 0.1, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: base * 1.2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, base * 0.08)
                .padding(.vertical, base * 0.05)
                .background(BubbleShape(tail: base * 0.08).fill(.white))
                .overlay(BubbleShape(tail: base * 0.08).stroke(.black, lineWidth: max(base * 0.012, 1)))
                .padding(.bottom, base * 0.08)

        case .tape:
            Text(sticker.text)
                .font(.custom("Noteworthy-Bold", size: base * 0.11))
                .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.2))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, base * 0.1)
                .padding(.vertical, base * 0.035)
                .background(Color(red: 0.96, green: 0.86, blue: 0.62).opacity(0.85))
        }
    }
}

/// CAUTION テープのふちの、黄色と黒の斜めのしま
private struct CautionStripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let step = max(size.height * 2, 2)
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                path.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 1, green: 0.84, blue: 0.0)))
                x += step
            }
        }
    }
}

/// ふきだし：角の丸い四角と、左下のしっぽ
private struct BubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: min(rect.height / 2, tail * 2.5))
        path.move(to: CGPoint(x: rect.minX + tail * 1.5, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + tail * 0.8, y: rect.maxY + tail))
        path.addLine(to: CGPoint(x: rect.minX + tail * 3, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

/// PencilKit の描くところ。ペンのモードのときだけ道具パレットを出す
private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    let drawing: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.marker, color: .systemPink, width: 18)
        context.coordinator.picker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        let picker = context.coordinator.picker
        let show = drawing
        DispatchQueue.main.async {
            picker.setVisible(show, forFirstResponder: view)
            if show { view.becomeFirstResponder() } else { view.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let picker = PKToolPicker()
    }
}
