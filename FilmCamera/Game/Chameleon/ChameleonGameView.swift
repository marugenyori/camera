import PhotosUI
import SwiftUI

/// 隠しゲーム「かくれカメレオン」：真っ白な体に色を塗って背景にとけこむ、お絵描きかくれんぼ。
/// みんなで：1 台をまわして、隠れる人が順番に塗って隠れ、最後に鬼が探す（撃てる回数と時間に限りあり）。
/// ひとりで：コンピュータが背景を写し取って隠れ、あなたが探す（レベルが上がるほど見分けにくい）
struct ChameleonGameView: View {
    let initialImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = ChameleonGame()

    var body: some View {
        ZStack {
            ChameleonTheme.background.ignoresSafeArea()
            switch game.phase {
            case .setup:
                ChameleonSetupView(game: game, initialImage: initialImage) { dismiss() }
            case .hideHandoff(let index):
                HandoffView(icon: "eye.slash.fill",
                            title: "\(game.hiders[index].name) の番",
                            message: "ほかの人は見ないでね。\n\(Int(ChameleonGame.hideSeconds)) 秒で体に色を塗って、背景にとけこもう。",
                            button: "かくれる") { game.beginHiding(index) }
            case .hiding(let index):
                HideView(game: game, index: index)
            case .seekHandoff:
                HandoffView(icon: "scope",
                            title: "鬼の番",
                            message: "\(game.hiders.count) 人がどこかにかくれています。\n撃てるのは \(game.hiders.count + 3) 発、時間は \(Int(ChameleonGame.seekSeconds)) 秒。",
                            button: "さがす") { game.beginSeeking() }
            case .seeking:
                SeekView(game: game)
            case .result:
                ResultView(game: game) { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onDisappear { GameAudio.shared.stop() }
    }
}

enum ChameleonTheme {
    static let background = Color(red: 0.06, green: 0.08, blue: 0.09)
    static let panel = Color(red: 0.12, green: 0.15, blue: 0.16)
    static let accent = Color(red: 0.55, green: 0.95, blue: 0.4)
    static let warning = Color(red: 1, green: 0.45, blue: 0.35)
}

// MARK: - はじめの画面

private struct ChameleonSetupView: View {
    @ObservedObject var game: ChameleonGame
    let initialImage: UIImage?
    let onClose: () -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var thumbnails: [StagePreset: UIImage] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }
                    Spacer()
                    if game.mode == .solo {
                        Text("レベル \(game.level)")
                            .font(.subheadline.weight(.heavy).monospacedDigit())
                            .foregroundStyle(ChameleonTheme.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("かくれカメレオン")
                        .font(.system(.largeTitle, design: .rounded).weight(.black))
                    Text("真っ白な体に色を塗って、背景にとけこむかくれんぼ")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Picker("あそびかた", selection: $game.mode) {
                    ForEach(ChameleonGame.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if game.mode == .party { players } else {
                    Text("コンピュータが背景をまねして隠れます。少ない弾で全部見つけよう。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }

                stages

                Button {
                    game.start()
                } label: {
                    Text(game.mode == .party ? "はじめる" : "さがしにいく")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(game.canStart ? ChameleonTheme.accent : Color.gray))
                }
                .disabled(!game.canStart)
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .task {
            if thumbnails.isEmpty {
                for preset in StagePreset.allCases { thumbnails[preset] = preset.thumbnail() }
            }
            if game.stage == nil {
                if let initialImage { game.setStage(initialImage, title: "最後に撮った写真") }
                else { game.setStage(StagePreset.leaves.render(), title: StagePreset.leaves.title) }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    game.setStage(image, title: "選んだ写真")
                }
            }
        }
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("かくれる人").font(.headline)
                Spacer()
                Stepper("\(game.names.count) 人", value: Binding(
                    get: { game.names.count },
                    set: { count in
                        while game.names.count < count { game.names.append("プレイヤー\(game.names.count + 1)") }
                        while game.names.count > count { game.names.removeLast() }
                    }), in: 1...4)
                    .fixedSize()
            }
            ForEach(game.names.indices, id: \.self) { index in
                TextField("名前", text: $game.names[index])
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ChameleonTheme.panel))
            }
            Text("このほかに、鬼が 1 人。iPhone をまわして遊びます。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ステージ").font(.headline)
                Spacer()
                Text(game.stageTitle).font(.caption).foregroundStyle(ChameleonTheme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let initialImage {
                        stageCard(image: initialImage, title: "最後の写真", selected: game.stageTitle == "最後に撮った写真") {
                            game.setStage(initialImage, title: "最後に撮った写真")
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled").font(.title2)
                            Text("写真を選ぶ").font(.caption2.weight(.bold))
                        }
                        .frame(width: 96, height: 128)
                        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35),
                                                                                     style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    ForEach(StagePreset.allCases) { preset in
                        stageCard(image: thumbnails[preset], title: preset.title, selected: game.stageTitle == preset.title) {
                            game.setStage(preset.render(), title: preset.title)
                        }
                    }
                }
            }
            Text("撮った写真をステージにすると、いつもの景色でかくれんぼできます。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func stageCard(image: UIImage?, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Color.white.opacity(0.08)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                Text(title).font(.caption2.weight(.bold)).padding(6)
            }
            .frame(width: 96, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ChameleonTheme.accent, lineWidth: selected ? 3 : 0))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 渡す画面

private struct HandoffView: View {
    let icon: String
    let title: String
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(ChameleonTheme.accent)
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.black))
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button(action: action) {
                Text(button)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ChameleonTheme.accent))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        .foregroundStyle(.white)
        .padding(20)
    }
}

// MARK: - ステージの表示（ズームと移動つき）

/// ステージの見え方：画面に合わせた縮尺 k、ズーム、画面の真ん中に来るステージ上の点
struct StageView: Equatable {
    var size: CGSize
    var zoom: CGFloat = 1
    var focus = CGPoint(x: ChameleonGame.stageSize.width / 2, y: ChameleonGame.stageSize.height / 2)

    var fit: CGFloat { size.width / ChameleonGame.stageSize.width }
    var scale: CGFloat { fit * zoom }

    func toStage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: focus.x + (point.x - size.width / 2) / scale, y: focus.y + (point.y - size.height / 2) / scale)
    }

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - focus.x) * scale + size.width / 2, y: (point.y - focus.y) * scale + size.height / 2)
    }

    /// ステージの外が見えないように、真ん中の点をおさえる
    func clamped() -> StageView {
        var copy = self
        let halfW = size.width / 2 / scale, halfH = size.height / 2 / scale
        let w = ChameleonGame.stageSize.width, h = ChameleonGame.stageSize.height
        copy.focus.x = halfW * 2 >= w ? w / 2 : min(max(focus.x, halfW), w - halfW)
        copy.focus.y = halfH * 2 >= h ? h / 2 : min(max(focus.y, halfH), h - halfH)
        return copy
    }
}

/// ステージとキャラを描く。outline は塗る人用（体のふちと目）、reveal は見つかった・結果の表示
private struct StageCanvas: View {
    let stage: UIImage?
    let hiders: [ChameleonGame.Hider]
    let view: StageView
    var outlineIndex: Int? = nil
    var revealAll = false

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: view.size.width / 2, y: view.size.height / 2)
            context.scaleBy(x: view.scale, y: view.scale)
            context.translateBy(x: -view.focus.x, y: -view.focus.y)
            if let stage {
                context.draw(Image(uiImage: stage), in: CGRect(origin: .zero, size: ChameleonGame.stageSize))
            }
            for (index, hider) in hiders.enumerated() {
                var layer = context
                layer.translateBy(x: hider.center.x, y: hider.center.y)
                layer.rotate(by: .radians(hider.angle))
                layer.scaleBy(x: hider.scale, y: hider.scale)
                let parts = hider.shape.parts
                let outlined = index == outlineIndex
                let revealed = revealAll || hider.found
                if outlined || revealed {
                    // ふち：太い線を先に引き、その上に体を塗る（内側の線は体で隠れる）
                    let color: Color = revealed ? (hider.found ? ChameleonTheme.accent : ChameleonTheme.warning) : .white
                    for part in parts {
                        layer.stroke(part, with: .color(color.opacity(outlined ? 0.75 : 1)),
                                     lineWidth: (outlined ? 3 : 7) / hider.scale / max(view.scale, 0.01) * 1.2)
                    }
                }
                var skin = layer
                skin.clipToLayer { mask in
                    for part in parts { mask.fill(part, with: .color(.black)) }
                }
                skin.draw(Image(uiImage: hider.paint), in: HiderShape.box)
                if outlined, let eye = hider.shape.eye {
                    // 塗る人にだけ見える目
                    layer.stroke(Path(ellipseIn: CGRect(x: eye.x - 6, y: eye.y - 6, width: 12, height: 12)),
                                 with: .color(.black.opacity(0.55)), lineWidth: 2)
                    layer.fill(Path(ellipseIn: CGRect(x: eye.x - 2.5, y: eye.y - 2.5, width: 5, height: 5)),
                               with: .color(.black.opacity(0.55)))
                }
            }
        }
    }
}

// MARK: - かくれる（塗って、動かす）

private struct HideView: View {
    @ObservedObject var game: ChameleonGame
    let index: Int
    @State private var painting = false
    @State private var view = StageView(size: .zero)
    @State private var lastStagePoint: CGPoint?
    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGFloat?
    @State private var angleStart: Double?

    private static let swatches: [Color] = [
        .white, Color(white: 0.75), Color(white: 0.45), .black,
        Color(red: 0.85, green: 0.25, blue: 0.2), Color(red: 1, green: 0.55, blue: 0.2), Color(red: 1, green: 0.85, blue: 0.3),
        Color(red: 0.45, green: 0.75, blue: 0.3), Color(red: 0.15, green: 0.45, blue: 0.25), Color(red: 0.3, green: 0.6, blue: 0.9),
        Color(red: 0.2, green: 0.3, blue: 0.6), Color(red: 0.6, green: 0.35, blue: 0.75), Color(red: 1, green: 0.6, blue: 0.75),
        Color(red: 0.55, green: 0.38, blue: 0.25),
    ]

    private var hider: ChameleonGame.Hider? { game.hiders.indices.contains(index) ? game.hiders[index] : nil }

    var body: some View {
        VStack(spacing: 10) {
            header
            GeometryReader { geo in
                let current = view.size == geo.size ? view : StageView(size: geo.size)
                StageCanvas(stage: game.stage, hiders: game.hiders.filter { $0.id == hider?.id },
                            view: current, outlineIndex: 0)
                    .contentShape(Rectangle())
                    .gesture(painting ? paintGesture : nil)
                    .gesture(painting ? nil : moveGesture)
                    .simultaneousGesture(painting ? nil : scaleGesture)
                    .simultaneousGesture(painting ? nil : rotateGesture)
                    .onAppear { view = StageView(size: geo.size) }
                    .onChange(of: geo.size) { _, size in view.size = size; updateZoom() }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topLeading) { hint }
            controls
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
        .onChange(of: painting) { _, _ in updateZoom() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(hider?.name ?? "").font(.headline)
                Text("かくれる番").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            CountdownBadge(deadline: game.deadline, total: ChameleonGame.hideSeconds) {
                game.finishHiding(index)
            }
            Button {
                game.finishHiding(index)
            } label: {
                Text("できた")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(ChameleonTheme.accent))
            }
        }
        .padding(.top, 6)
    }

    private var hint: some View {
        Text(painting ? (game.tool == .dropper ? "背景をさわると、その色を取ります" : "体をなぞって塗る（大きく見ています）")
                      : "ドラッグで動かす・2 本指で大きさと向き")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(8)
    }

    /// 塗るときはキャラのまわりを大きく見る
    private func updateZoom() {
        guard let hider else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if painting {
                view.zoom = max(1.6, min(4, 2.6 / hider.scale))
                view.focus = hider.center
            } else {
                view.zoom = 1
                view.focus = CGPoint(x: ChameleonGame.stageSize.width / 2, y: ChameleonGame.stageSize.height / 2)
            }
            view = view.clamped()
        }
    }

    // MARK: 操作

    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = view.toStage(value.location)
                switch game.tool {
                case .dropper:
                    if lastStagePoint == nil, let color = game.sampleColor(at: point) {
                        game.color = color
                        game.tool = .brush
                        GameAudio.shared.tick()
                    }
                    lastStagePoint = point
                case .fill:
                    if lastStagePoint == nil {
                        game.beginStroke(index)
                        game.fill(index)
                    }
                    lastStagePoint = point
                default:
                    if lastStagePoint == nil { game.beginStroke(index) }
                    let width = game.brushSize / view.scale
                    game.stroke(index, from: lastStagePoint ?? point, to: point, width: width)
                    lastStagePoint = point
                }
            }
            .onEnded { _ in lastStagePoint = nil }
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard let hider else { return }
                if dragStart == nil { dragStart = hider.center }
                let start = dragStart ?? hider.center
                game.move(index, center: CGPoint(x: start.x + value.translation.width / view.scale,
                                                 y: start.y + value.translation.height / view.scale))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var scaleGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let hider else { return }
                if scaleStart == nil { scaleStart = hider.scale }
                game.move(index, scale: (scaleStart ?? 1) * value.magnification)
            }
            .onEnded { _ in scaleStart = nil }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard let hider else { return }
                if angleStart == nil { angleStart = hider.angle }
                game.move(index, angle: (angleStart ?? 0) + value.rotation.radians)
            }
            .onEnded { _ in angleStart = nil }
    }

    // MARK: 道具

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: $painting) {
                    Label("動かす", systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(false)
                    Label("塗る", systemImage: "paintbrush.fill").tag(true)
                }
                .pickerStyle(.segmented)
                Button {
                    game.undoStroke(index)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.headline)
                        .frame(width: 40, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ChameleonTheme.panel))
                }
                .disabled(!game.canUndo(index))
            }
            if painting { paintTools } else { shapes }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ChameleonTheme.panel))
    }

    private var shapes: some View {
        HStack(spacing: 8) {
            ForEach(HiderShape.allCases) { shape in
                let selected = hider?.shape == shape
                Button {
                    game.setShape(index, shape)
                    GameAudio.shared.tick()
                } label: {
                    VStack(spacing: 4) {
                        ShapeIcon(shape: shape)
                            .frame(width: 46, height: 32)
                        Text(shape.title).font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? ChameleonTheme.accent.opacity(0.25) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? ChameleonTheme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var paintTools: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(ChameleonGame.Tool.allCases) { tool in
                    let selected = game.tool == tool
                    Button {
                        game.tool = tool
                        GameAudio.shared.tick()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tool.systemImage).font(.body)
                            Text(tool.title).font(.system(size: 9, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.black : Color.white)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? ChameleonTheme.accent : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Circle()
                    .fill(game.color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.swatches.indices, id: \.self) { i in
                            Button {
                                game.color = Self.swatches[i]
                                if game.tool == .dropper || game.tool == .eraser { game.tool = .brush }
                            } label: {
                                Circle()
                                    .fill(Self.swatches[i])
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                }
                ColorPicker("", selection: $game.color, supportsOpacity: false)
                    .labelsHidden()
            }
            HStack(spacing: 10) {
                Image(systemName: "circle.fill").font(.system(size: 6))
                Slider(value: $game.brushSize, in: 4...40)
                    .tint(ChameleonTheme.accent)
                Image(systemName: "circle.fill").font(.system(size: 16))
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// 形を選ぶボタンの小さい絵
private struct ShapeIcon: View {
    let shape: HiderShape

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 200, size.height / 140)
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            for part in shape.parts { context.fill(part, with: .color(.white)) }
        }
    }
}

/// 残り時間の丸いメーター。0 になったら onTimeout
private struct CountdownBadge: View {
    let deadline: Date
    let total: Double
    let onTimeout: () -> Void
    @State private var fired = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let left = max(0, deadline.timeIntervalSince(timeline.date))
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: left / total)
                    .stroke(left < 10 ? ChameleonTheme.warning : ChameleonTheme.accent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(left.rounded(.up)))")
                    .font(.caption.weight(.heavy).monospacedDigit())
            }
            .frame(width: 40, height: 40)
            .onChange(of: left <= 0) { _, done in
                if done && !fired {
                    fired = true
                    onTimeout()
                }
            }
        }
    }
}

// MARK: - さがす

private struct SeekView: View {
    @ObservedObject var game: ChameleonGame
    @State private var view = StageView(size: .zero)
    @State private var zoomStart: CGFloat?
    @State private var panStart: CGPoint?
    @State private var effects: [ShotEffect] = []

    struct ShotEffect: Identifiable {
        let id = UUID()
        let point: CGPoint
        let hit: String?
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            GeometryReader { geo in
                ZStack {
                    StageCanvas(stage: game.stage, hiders: game.hiders, view: view.size == geo.size ? view : StageView(size: geo.size))
                    ForEach(effects) { effect in
                        ShotMark(effect: effect, view: view)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in shoot(at: value.location) })
                .simultaneousGesture(panGesture)
                .simultaneousGesture(zoomGesture)
                .onAppear { view = StageView(size: geo.size) }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                Text("タップで撃つ・2 本指で拡大・ドラッグで見回す")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("みつけた \(game.hiders.filter(\.found).count) / \(game.hiders.count)")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 3) {
                    ForEach(0..<(game.hiders.count + 3), id: \.self) { i in
                        Capsule()
                            .fill(i < game.shotsLeft ? ChameleonTheme.accent : Color.white.opacity(0.15))
                            .frame(width: 7, height: 16)
                    }
                }
            }
            Spacer()
            CountdownBadge(deadline: game.deadline, total: ChameleonGame.seekSeconds) {
                game.finishSeeking()
            }
        }
        .padding(.top, 6)
    }

    private func shoot(at location: CGPoint) {
        guard game.shotsLeft > 0 else { return }
        let point = view.toStage(location)
        let hit = game.shoot(at: point)
        UIImpactFeedbackGenerator(style: hit == nil ? .rigid : .heavy).impactOccurred()
        let effect = ShotEffect(point: point, hit: hit?.name)
        effects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            effects.removeAll { $0.id == effect.id }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if panStart == nil { panStart = view.focus }
                guard let start = panStart else { return }
                view.focus = CGPoint(x: start.x - value.translation.width / view.scale,
                                     y: start.y - value.translation.height / view.scale)
                view = view.clamped()
            }
            .onEnded { _ in panStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = view.zoom }
                view.zoom = min(4, max(1, (zoomStart ?? 1) * value.magnification))
                view = view.clamped()
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// 撃った場所の印：はずれは小さな土けむり、当たりは「みつけた！」
private struct ShotMark: View {
    let effect: SeekView.ShotEffect
    let view: StageView
    @State private var go = false

    var body: some View {
        let point = view.toView(effect.point)
        ZStack {
            Circle()
                .stroke(effect.hit == nil ? Color.white : ChameleonTheme.accent, lineWidth: 3)
                .frame(width: go ? 70 : 10, height: go ? 70 : 10)
                .opacity(go ? 0 : 1)
            Image(systemName: effect.hit == nil ? "xmark" : "scope")
                .font(.title2.weight(.bold))
                .foregroundStyle(effect.hit == nil ? Color.white : ChameleonTheme.accent)
                .opacity(go ? 0 : 1)
            if let name = effect.hit {
                Text("みつけた！\n\(name)")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ChameleonTheme.accent)
                    .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    .offset(y: go ? -60 : -20)
                    .scaleEffect(go ? 1.15 : 0.6)
            }
        }
        .position(point)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { go = true } }
    }
}

// MARK: - 結果

private struct ResultView: View {
    @ObservedObject var game: ChameleonGame
    let onClose: () -> Void

    private var allFound: Bool { game.hiders.allSatisfy(\.found) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded).weight(.black))
                        .foregroundStyle(allFound ? ChameleonTheme.accent : ChameleonTheme.warning)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 20)
                GeometryReader { geo in
                    StageCanvas(stage: game.stage, hiders: game.hiders, view: StageView(size: geo.size), revealAll: true)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("緑のふち＝見つかった　赤のふち＝にげきった")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(game.hiders) { hider in
                    HStack(spacing: 12) {
                        HiderPortrait(hider: hider)
                            .frame(width: 80, height: 56)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hider.name).font(.headline)
                            Text(hider.found ? "\(Int(hider.foundAfter ?? 0)) 秒で見つかった" : "にげきった！")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(hider.found ? .white.opacity(0.6) : ChameleonTheme.accent)
                        }
                        Spacer()
                        Image(systemName: hider.found ? "scope" : "crown.fill")
                            .foregroundStyle(hider.found ? Color.white.opacity(0.4) : Color.yellow)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ChameleonTheme.panel))
                }
                buttons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        if game.mode == .solo { return allFound ? "クリア！" : "見のがした…" }
        return allFound ? "鬼の勝ち！" : "かくれた人の勝ち！"
    }

    private var subtitle: String {
        if game.mode == .solo {
            return allFound ? "レベル \(game.level) に進みます" : "もう一度ためしてみよう"
        }
        let survivors = game.hiders.filter { !$0.found }.map(\.name)
        return survivors.isEmpty ? "全員見つけた！" : survivors.joined(separator: "、") + " がにげきった"
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                if game.mode == .solo { game.nextRound() } else { game.start() }
            } label: {
                Text(game.mode == .solo ? (allFound ? "次のレベル" : "もう一度") : "同じステージでもう一回")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ChameleonTheme.accent))
            }
            Button("ステージをえらびなおす") { game.again() }
                .font(.subheadline.weight(.bold))
                .padding(.vertical, 6)
            Button("やめる", action: onClose)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 8)
    }
}

/// 隠れた人の体の絵（結果の一覧用）
private struct HiderPortrait: View {
    let hider: ChameleonGame.Hider

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 200, size.height / 140) * 0.92
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            let parts = hider.shape.parts
            context.clipToLayer { mask in
                for part in parts { mask.fill(part, with: .color(.black)) }
            }
            context.draw(Image(uiImage: hider.paint), in: HiderShape.box)
        }
    }
}
