import Photos
import SwiftUI

/// 箱庭ゲームの画面。下の道具で地面を塗る・高さを変える・ものを置く・いきものを放す。
/// 指でなぞると続けて塗れる。2 本指で拡大、「見る」でなぞると動かせる。右上で回転・時間・天気
struct HakoniwaGameView: View {
    @StateObject private var model = HakoniwaModel()
    @Environment(\.dismiss) private var dismiss
    /// なぞっている間に塗ったマス（同じマスに何度も使わない）
    @State private var stroke: Set<Int> = []
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var confirmingNew = false
    @State private var toast: String?
    @State private var muted = GameAudio.shared.isMuted

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        HakoniwaRenderer.draw(&context, size: size, model: model, time: time)
                    }
                }
                .ignoresSafeArea()
                .gesture(dragGesture(size: geo.size))
                .simultaneousGesture(zoomGesture)
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if let toast {
                        Text(toast)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 10)
                            .transition(.opacity)
                    }
                    bottomPanel
                }
            }
        }
        .preferredColorScheme(.light)
        .task { await runClock() }
        .onDisappear {
            model.save()
            GameAudio.shared.stop()
        }
        .confirmationDialog("新しい箱庭を作りますか？", isPresented: $confirmingNew, titleVisibility: .visible) {
            ForEach(HakoniwaModel.Template.allCases) { template in
                Button(template.name) { model.newGarden(template) }
            }
        } message: {
            Text("いまの箱庭は消えます。")
        }
    }

    /// いきものを歩かせ、時間を進める（1 秒に 30 回）
    @MainActor
    private func runClock() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            model.tick(min(now.timeIntervalSince(last), 0.1))
            last = now
        }
    }

    // MARK: - さわる

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard zoomStart == nil else { return }
                if model.tool == .look {
                    if panStart == nil { panStart = model.pan }
                    if let start = panStart {
                        model.pan = CGSize(width: start.width + value.translation.width,
                                           height: start.height + value.translation.height)
                    }
                    return
                }
                guard let hit = HakoniwaRenderer.cell(at: value.location, size: size, model: model) else { return }
                let (x, y) = hit
                let key = model.index(x, y)
                guard !stroke.contains(key) else { return }
                // いきものは 1 回のタップで 1 匹だけ
                if model.tool == .critter, !stroke.isEmpty { return }
                stroke.insert(key)
                model.apply(at: x, y)
            }
            .onEnded { _ in
                if !stroke.isEmpty { model.save() }
                stroke = []
                panStart = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = model.zoom }
                if let start = zoomStart {
                    model.zoom = min(max(start * value.magnification, 0.6), 3.5)
                }
            }
            .onEnded { _ in zoomStart = nil }
    }

    // MARK: - 上の列

    private var topBar: some View {
        HStack(spacing: 10) {
            circleButton("xmark", label: "閉じる") { dismiss() }
            Text("ちいさな箱庭")
                .font(.headline.weight(.heavy))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            circleButton("rotate.left", label: "左に回す") { model.rotate(-1) }
            circleButton("rotate.right", label: "右に回す") { model.rotate(1) }
            Menu {
                Picker("時間", selection: $model.timeMode) {
                    ForEach(HakoniwaModel.TimeMode.allCases) { mode in
                        Label(mode.name, systemImage: mode.symbol).tag(mode)
                    }
                }
                Picker("天気", selection: $model.weather) {
                    ForEach(HakoniwaModel.Weather.allCases) { weather in
                        Label(weather.name, systemImage: weather.symbol).tag(weather)
                    }
                }
            } label: {
                circleLabel(model.timeMode.symbol)
            }
            .accessibilityLabel("時間と天気")
            Menu {
                Button {
                    takePhoto()
                } label: {
                    Label("写真に撮る", systemImage: "camera")
                }
                Button {
                    withAnimation { model.zoom = 1; model.pan = .zero }
                } label: {
                    Label("真ん中に戻す", systemImage: "scope")
                }
                Button {
                    muted.toggle()
                    GameAudio.shared.isMuted = muted
                } label: {
                    Label(muted ? "音を出す" : "音を消す", systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                }
                Button(role: .destructive) {
                    confirmingNew = true
                } label: {
                    Label("新しく作る", systemImage: "sparkles")
                }
            } label: {
                circleLabel("ellipsis")
            }
            .accessibilityLabel("メニュー")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleLabel(symbol)
        }
        .accessibilityLabel(label)
    }

    private func circleLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }

    // MARK: - 下の道具

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            palette
                .frame(height: 64)
            HStack(spacing: 4) {
                ForEach(HakoniwaModel.Tool.allCases) { tool in
                    let selected = model.tool == tool
                    Button {
                        model.tool = tool
                        GameAudio.shared.tick()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tool.symbol)
                                .font(.body.weight(.semibold))
                            Text(tool.name)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.95, green: 0.5, blue: 0.2))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var palette: some View {
        switch model.tool {
        case .ground:
            chips(HakoniwaModel.Palette.grounds, selected: model.ground, name: { $0.name }) { ground in
                model.ground = ground
            } preview: { ground in
                GroundSwatch(ground: ground)
            }
        case .height:
            HStack(spacing: 10) {
                ForEach(HakoniwaModel.HeightAction.allCases) { action in
                    let selected = model.heightAction == action
                    Button {
                        model.heightAction = action
                    } label: {
                        Label(action.name, systemImage: action == .up ? "arrow.up" : action == .down ? "arrow.down" : "equal")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color(red: 0.95, green: 0.5, blue: 0.2).opacity(0.25) : Color.white.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? Color(red: 0.95, green: 0.5, blue: 0.2) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .item:
            chips(HItem.allCases, selected: model.item, name: { $0.name }) { item in
                model.item = item
            } preview: { item in
                ItemPreview(item: item)
            }
        case .critter:
            chips(HCritterKind.allCases, selected: model.critterKind, name: { $0.name }) { kind in
                model.critterKind = kind
            } preview: { kind in
                CritterPreview(kind: kind)
            }
        case .erase:
            hint("eraser", "なぞると、置いたものといきものを消します（地面と高さはそのまま）")
        case .look:
            hint("hand.draw", "なぞると動かせます。2 本指で拡大・縮小。右上のボタンで回せます")
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func chips<T: Hashable & Identifiable, Preview: View>(
        _ values: [T], selected: T, name: @escaping (T) -> String, choose: @escaping (T) -> Void,
        @ViewBuilder preview: @escaping (T) -> Preview
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values) { value in
                    let isSelected = value == selected
                    Button {
                        choose(value)
                        GameAudio.shared.tick()
                    } label: {
                        VStack(spacing: 2) {
                            preview(value)
                                .frame(width: 44, height: 40)
                            Text(name(value))
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 58, height: 62)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color(red: 0.95, green: 0.5, blue: 0.2).opacity(0.25) : Color.white.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color(red: 0.95, green: 0.5, blue: 0.2) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(value))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 写真

    /// いまの箱庭を写真にして、写真アプリに保存する
    @MainActor
    private func takePhoto() {
        let size = CGSize(width: 1080 / 2, height: 1350 / 2)
        let time = Date().timeIntervalSinceReferenceDate
        let renderer = ImageRenderer(content:
            Canvas { context, canvasSize in
                HakoniwaRenderer.draw(&context, size: canvasSize, model: model, time: time)
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                show("写真アプリへの保存が許可されていません")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                GameAudio.shared.play(.complete)
                show("写真アプリに保存しました")
            } catch {
                show("保存できませんでした")
            }
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

extension HakoniwaModel {
    /// 道具の列に並べる順番
    enum Palette {
        static let grounds: [HGround] = [.grass, .meadow, .sand, .water, .path, .farm, .snow]
    }
}

// MARK: - 道具の見本

private struct GroundSwatch: View {
    let ground: HGround

    var body: some View {
        Canvas { context, size in
            let layout = HLayout(previewWidth: size.width * 0.9, at: CGPoint(x: size.width / 2, y: size.height * 0.45))
            let top = 0.0
            let a = layout.p(0, 0, top), b = layout.p(1, 0, top), c = layout.p(1, 1, top), d = layout.p(0, 1, top)
            func poly(_ points: [CGPoint]) -> Path {
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()
                }
            }
            context.fill(poly([d, c, layout.p(1, 1, -1.2), layout.p(0, 1, -1.2)]), with: .color(ground.band.opacity(0.85)))
            context.fill(poly([b, c, layout.p(1, 1, -1.2), layout.p(1, 0, -1.2)]), with: .color(ground.band))
            context.fill(poly([a, b, c, d]), with: .color(ground.top(true)))
        }
    }
}

private struct ItemPreview: View {
    let item: HItem

    var body: some View {
        Canvas { context, size in
            let width = item == .house || item == .tent ? size.width * 0.75 : size.width * 0.95
            let layout = HLayout(previewWidth: width, at: CGPoint(x: size.width / 2, y: size.height * 0.82))
            var glows: [(CGPoint, CGFloat)] = []
            HakoniwaRenderer.drawItem(&context, layout: layout, item: item, gx: 0, gy: 0, top: 0, tint: 0, seed: 3,
                                      time: 0, night: 0, glows: &glows)
        }
    }
}

private struct CritterPreview: View {
    let kind: HCritterKind

    var body: some View {
        Canvas { context, size in
            let layout = HLayout(previewWidth: size.width * 1.6, at: CGPoint(x: size.width / 2, y: size.height * 0.85))
            let critter = HCritter(kind: kind, x: 0.5, y: 0.5, tx: 1, ty: 0, tint: 0, wait: 1)
            HakoniwaRenderer.drawCritter(&context, layout: layout, critter: critter, top: 0, time: 0)
        }
    }
}
