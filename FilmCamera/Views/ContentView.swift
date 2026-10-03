import SwiftUI

/// 撮影画面。黒地に細い線と小さな等幅文字だけの、プロ機材風のミニマルな見た目
struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashOpacity = 0.0
    @State private var showingPhoto = false
    @State private var showingContactSettings = false
    @AppStorage("showGrid") private var showGrid = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                hud
                ZStack(alignment: .bottom) {
                    preview
                    VStack(spacing: 10) {
                        if camera.mode == .double && camera.captureKind == .photo && !camera.isDual {
                            exposureOptions
                        }
                        if camera.mode == .contact && !camera.isDual {
                            Button {
                                showingContactSettings = true
                            } label: {
                                Label("\(camera.contactLayout.title)  フィルタと並べ方", systemImage: "square.grid.2x2")
                                    .hudChip()
                            }
                            .disabled(camera.isRecording)
                        }
                        if !camera.isDual {
                            ZoomRuler(zoom: camera.zoom,
                                      range: camera.zoomRange,
                                      presets: zoomPresets,
                                      onLever: { camera.zoomLever($0) },
                                      onPreset: { camera.zoom(to: $0) },
                                      onScrub: { camera.scrubZoom(to: $0) })
                        }
                    }
                    .padding(.bottom, 12)
                }
                ModeDial(selection: $camera.mode)
                    .disabled(camera.isRecording)
                    .opacity(camera.isRecording ? 0.4 : 1)
                    .padding(.top, 8)
                kindPicker
                controls
            }

            // フラッシュで撮ったときに画面を白く光らせる
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background:
                if camera.isRecording { camera.stopRecording() }
                camera.stop()
            default: break
            }
        }
        .onChange(of: camera.shotCount) { _, _ in
            guard camera.mode.usesDepth else { return }
            flashOpacity = 0.9
            withAnimation(.easeOut(duration: 0.4)) { flashOpacity = 0 }
        }
        .onChange(of: camera.message) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                camera.message = nil
            }
        }
        .sensoryFeedback(.impact, trigger: camera.shotCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.isRecording)
        .sensoryFeedback(.selection, trigger: camera.mode)
        // ズーム中は 0.1× ごとにカチカチと手応えを返す（ズームリングの目盛りのように）
        .sensoryFeedback(.selection, trigger: Int((camera.zoom * 10).rounded()))
        .sheet(isPresented: $showingContactSettings) {
            ContactSettingsView(camera: camera)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPhoto) {
            if let photo = camera.lastPhoto {
                PhotoSheet(image: photo)
            }
        }
    }

    // MARK: - 上の表示（モード・状態・切り替え）

    private var hud: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ModeSwatch(mode: camera.mode)
                    .frame(width: 22, height: 8)
                Text(camera.mode.code)
                    .foregroundStyle(.white)
            }
            .hudText()
            .animation(.snappy, value: camera.mode)

            Spacer(minLength: 8)
            statusReadout
            Spacer(minLength: 8)

            HStack(spacing: 16) {
                HUDToggle(title: "DATE", isOn: camera.dateStamp, label: "日付") {
                    camera.dateStamp.toggle()
                }
                HUDToggle(title: "GRID", isOn: showGrid, label: "グリッド") {
                    showGrid.toggle()
                }
                if CameraModel.isDualSupported {
                    HUDToggle(title: "DUAL", isOn: camera.isDual, label: "前後同時") {
                        camera.isDual.toggle()
                    }
                    .disabled(camera.isRecording || camera.isSaving)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    @ViewBuilder
    private var statusReadout: some View {
        if camera.isRecording, let start = camera.recordingStartedAt {
            TimelineView(.periodic(from: start, by: 0.5)) { context in
                let seconds = Int(context.date.timeIntervalSince(start))
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text(String(format: "REC %02d:%02d", seconds / 60, seconds % 60))
                        .foregroundStyle(.white)
                }
                .hudText()
            }
        } else if camera.mode == .double && !camera.exposures.isEmpty && !camera.isBursting {
            Button {
                camera.discardExposures()
            } label: {
                HStack(spacing: 5) {
                    Text("\(camera.exposures.count)/\(camera.exposureCount)")
                    Image(systemName: "arrow.uturn.backward")
                }
                .hudText()
                .foregroundStyle(.tint)
            }
            .accessibilityLabel("撮り直す")
        } else if camera.mode.usesDepth && camera.isDepthActive && !camera.isDual {
            Text("DEPTH")
                .hudText()
                .foregroundStyle(.tint)
        } else if !camera.isDual {
            Text(ZoomRuler.label(camera.zoom) + "×")
                .hudText()
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - プレビュー

    private var preview: some View {
        CameraPreview(model: camera)
            .overlay { ViewfinderFrame(showGrid: showGrid && camera.mode != .contact) }
            .overlay { statusOverlay }
            .overlay(alignment: .top) {
                if let message = camera.message {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15), lineWidth: 0.5))
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard !camera.isRecording else { return }
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height) else { return }
                    shiftMode(by: dx < 0 ? 1 : -1)
                }
            )
            .onTapGesture(count: 2) {
                guard !camera.isRecording && !camera.isDual else { return }
                camera.switchCamera()
            }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch camera.status {
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("カメラの使用が許可されていません")
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        case .unavailable:
            VStack(spacing: 8) {
                Image(systemName: "camera.metering.unknown").font(.largeTitle)
                Text("カメラが見つかりません")
            }
            .foregroundStyle(.white.opacity(0.8))
        case .idle:
            ProgressView().tint(.white)
        case .running:
            EmptyView()
        }
    }

    // MARK: - ズーム

    private var zoomPresets: [CGFloat] {
        [0.5, 1, 2, 5].filter { camera.zoomRange.contains($0) || abs($0 - camera.zoomRange.lowerBound) < 0.02 }
    }

    // MARK: - 写真／ビデオ

    private var kindPicker: some View {
        HStack(spacing: 30) {
            kindButton("PHOTO", kind: .photo, label: "写真")
            kindButton("VIDEO", kind: .video, label: "ビデオ")
                .disabled(camera.isDual)
                .opacity(camera.isDual ? 0.35 : 1)
        }
        .disabled(camera.isRecording || camera.isSaving)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func kindButton(_ title: String, kind: CameraModel.CaptureKind, label: String) -> some View {
        let selected = camera.captureKind == kind
        return Button {
            withAnimation(.snappy) { camera.captureKind = kind }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .hudText()
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.4))
                Circle()
                    .fill(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.clear))
                    .frame(width: 4, height: 4)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - 多重露光の設定

    private var exposureOptions: some View {
        HStack(spacing: 4) {
            ForEach(2...4, id: \.self) { count in
                let selected = camera.exposureCount == count
                Button {
                    camera.exposureCount = count
                } label: {
                    Text("\(count)枚")
                        .hudText()
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                        .frame(width: 46, height: 28)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 18).padding(.horizontal, 4)
            Menu {
                Picker("撮り方", selection: $camera.burstInterval) {
                    ForEach(CameraModel.burstIntervals, id: \.self) { interval in
                        Text(Self.burstLabel(interval)).tag(interval)
                    }
                }
            } label: {
                Label(Self.burstLabel(camera.burstInterval), systemImage: "timer")
                    .hudText()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .disabled(camera.isBursting || !camera.exposures.isEmpty)
    }

    private static func burstLabel(_ interval: Double) -> String {
        if interval == 0 { return "手動" }
        let seconds = interval < 1 ? String(format: "%.1f", interval) : String(format: "%.0f", interval)
        return interval < CameraModel.fastBurstLimit
            ? "\(seconds)秒ごと（1200万画素）"
            : "\(seconds)秒ごと"
    }

    private func shiftMode(by step: Int) {
        let all = LookMode.allCases
        guard let index = all.firstIndex(of: camera.mode) else { return }
        let next = index + step
        guard all.indices.contains(next) else { return }
        withAnimation(.snappy) { camera.mode = all[next] }
    }

    // MARK: - シャッターなど

    private var controls: some View {
        HStack {
            Button {
                showingPhoto = true
            } label: {
                Group {
                    if let photo = camera.lastPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
            .disabled(camera.lastPhoto == nil || camera.isRecording)
            .accessibilityLabel("最後に撮った写真")

            Spacer()

            ShutterButton(kind: camera.captureKind,
                          isRecording: camera.isRecording,
                          isBusy: camera.isSaving) {
                camera.shutterPressed()
            }
            .disabled(camera.status != .running || (camera.isSaving && !camera.isRecording))

            Spacer()

            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
            .disabled(camera.status != .running || camera.isRecording || camera.isDual)
            .opacity(camera.isDual ? 0.35 : 1)
            .accessibilityLabel("カメラを切り替え")
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .padding(.bottom, 20)
    }
}

// MARK: - モードの見た目（略号と色見本）

extension LookMode {
    /// 上の表示に出す英字の略号
    var code: String {
        switch self {
        case .film: return "FILM"
        case .flash: return "FLASH"
        case .warmFlash: return "FLASH W"
        case .iwai: return "IWAI"
        case .cross: return "CROSS"
        case .harinezumi: return "HARI"
        case .warmHarinezumi: return "HARI W"
        case .double: return "MULTI"
        case .contact: return "SPLIT"
        }
    }

    /// そのモードの写りを表す色（参考写真から拾った代表色）
    var swatch: [Color] {
        switch self {
        case .film: return [Color(hex: 0xEBD6B0), Color(hex: 0xD99A62), Color(hex: 0x76876A)]
        case .flash: return [Color(hex: 0xF5F2EC), Color(hex: 0xE0A688), Color(hex: 0x1A1D24)]
        case .warmFlash: return [Color(hex: 0xFFE0A8), Color(hex: 0xE8843E), Color(hex: 0x2B1A10)]
        case .iwai: return [Color(hex: 0xE4F4F8), Color(hex: 0x5EC2E6), Color(hex: 0x1B2A4E)]
        case .cross: return [Color(hex: 0xF2C14E), Color(hex: 0xC2405A), Color(hex: 0x2B6F8A)]
        case .harinezumi: return [Color(hex: 0xD23C96), Color(hex: 0x5DD13A), Color(hex: 0x4A3AA6)]
        case .warmHarinezumi: return [Color(hex: 0xE6A0B5), Color(hex: 0xD88E2C), Color(hex: 0x1E3D8C)]
        case .double: return [Color(hex: 0xDADADA), Color(hex: 0x8E8E8E), Color(hex: 0x3C3C3C)]
        case .contact: return [Color(hex: 0xEBD6B0), Color(hex: 0x5EC2E6), Color(hex: 0xD23C96)]
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 部品

/// モードの色見本（細い帯）
private struct ModeSwatch: View {
    let mode: LookMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(mode.swatch.enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .clipShape(Capsule())
    }
}

/// 上の表示の、文字だけの切り替え（オンのときはテーマ色と下線）
private struct HUDToggle: View {
    let title: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .hudText()
                    .foregroundStyle(isOn ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.45)))
                Rectangle()
                    .fill(isOn ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.clear))
                    .frame(height: 1)
            }
            .fixedSize()
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "オン" : "オフ")
    }
}

/// ファインダーの枠：写真の範囲（縦 4:3）の四隅に細いかぎ括弧、必要なら三分割の線
private struct ViewfinderFrame: View {
    let showGrid: Bool

    var body: some View {
        GeometryReader { geo in
            let aspect: CGFloat = 3.0 / 4.0
            let width = min(geo.size.width, geo.size.height * aspect)
            let height = width / aspect
            let rect = CGRect(x: (geo.size.width - width) / 2, y: (geo.size.height - height) / 2,
                              width: width, height: height).insetBy(dx: 12, dy: 12)
            let arm: CGFloat = 16
            ZStack {
                Path { path in
                    let corners: [(CGPoint, CGFloat, CGFloat)] = [
                        (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
                        (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                        (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
                        (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
                    ]
                    for (corner, dx, dy) in corners {
                        path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                        path.addLine(to: corner)
                        path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
                    }
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1)

                if showGrid {
                    Path { path in
                        for i in 1...2 {
                            let x = rect.minX + rect.width * CGFloat(i) / 3
                            path.move(to: CGPoint(x: x, y: rect.minY))
                            path.addLine(to: CGPoint(x: x, y: rect.maxY))
                            let y = rect.minY + rect.height * CGFloat(i) / 3
                            path.move(to: CGPoint(x: rect.minX, y: y))
                            path.addLine(to: CGPoint(x: rect.maxX, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// ズームの目盛り。レンズのリングのように、倍率に合わせて目盛りが流れる。
/// なぞると倍率が追いかけ、数字を押すとその倍率まで一定の速さで動き、W / T は押している間だけ動く
private struct ZoomRuler: View {
    let zoom: CGFloat
    let range: ClosedRange<CGFloat>
    let presets: [CGFloat]
    let onLever: (Int) -> Void
    let onPreset: (CGFloat) -> Void
    let onScrub: (CGFloat) -> Void

    @State private var dragStartZoom: CGFloat?
    /// 倍率が 2 倍になるごとの目盛りの間隔
    private let pointsPerStop: CGFloat = 60

    var body: some View {
        HStack(spacing: 2) {
            ZoomLever(title: "W") { onLever($0 ? -1 : 0) }
            GeometryReader { geo in
                let mid = geo.size.width / 2
                let current = log2(max(zoom, 0.01))
                ZStack {
                    Canvas { context, size in
                        let low = Int((log2(range.lowerBound) * 10).rounded(.up))
                        let high = Int((log2(range.upperBound) * 10).rounded(.down))
                        guard low <= high else { return }
                        for step in low...high {
                            let x = mid + (CGFloat(step) / 10 - current) * pointsPerStop
                            guard x >= 0, x <= size.width else { continue }
                            let major = step % 10 == 0
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: 18))
                            tick.addLine(to: CGPoint(x: x, y: major ? 30 : 25))
                            context.stroke(tick, with: .color(.white.opacity(major ? 0.85 : 0.35)), lineWidth: 1)
                        }
                    }
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            onPreset(preset)
                        } label: {
                            Text(Self.label(preset))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 30, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: mid + (log2(preset) - current) * pointsPerStop, y: 42)
                    }
                    Text(Self.label(zoom) + "×")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.tint)
                        .position(x: mid, y: 7)
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 1.5, height: 18)
                        .position(x: mid, y: 24)
                }
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.2),
                                           .init(color: .black, location: 0.8),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = dragStartZoom ?? zoom
                            if dragStartZoom == nil { dragStartZoom = zoom }
                            let target = start * pow(2, -value.translation.width / pointsPerStop)
                            onScrub(min(max(target, range.lowerBound), range.upperBound))
                        }
                        .onEnded { _ in dragStartZoom = nil }
                )
            }
            .frame(width: 190, height: 52)
            ZoomLever(title: "T") { onLever($0 ? 1 : 0) }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ズーム \(Self.label(zoom))倍")
    }

    static func label(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() && rounded >= 1
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }
}

/// 押している間だけ動くズームレバー（離すと止まる）
private struct ZoomLever: View {
    let title: String
    let onPress: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(title)
            .hudText()
            .foregroundStyle(pressed ? Color.black : Color.white.opacity(0.85))
            .frame(width: 34, height: 34)
            .background(Circle().fill(pressed ? Color.white : Color.clear))
            .overlay(Circle().stroke(.white.opacity(pressed ? 0 : 0.25), lineWidth: 0.5))
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onPress(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        onPress(false)
                    }
            )
            .accessibilityLabel(title == "W" ? "広角へズーム" : "望遠へズーム")
    }
}

/// モードを選ぶダイヤル。横に回して、真ん中に来たモードになる（押しても選べる）
private struct ModeDial: View {
    @Binding var selection: LookMode
    @State private var centered: LookMode?
    private let itemWidth: CGFloat = 86

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(LookMode.allCases) { mode in
                        let selected = mode == selection
                        Button {
                            withAnimation(.snappy) { centered = mode }
                        } label: {
                            VStack(spacing: 7) {
                                Text(mode.title)
                                    .font(.footnote.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.4))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                ModeSwatch(mode: mode)
                                    .frame(width: selected ? 30 : 14, height: 3)
                                    .opacity(selected ? 1 : 0.4)
                            }
                            .frame(width: itemWidth, height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(mode)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - itemWidth) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered)
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black, location: 0.15),
                                       .init(color: .black, location: 0.85),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
        }
        .frame(height: 46)
        .overlay(alignment: .top) {
            // 真ん中の印
            Rectangle()
                .fill(.tint)
                .frame(width: 1.5, height: 5)
                .offset(y: -6)
        }
        .animation(.snappy, value: selection)
        .onChange(of: centered) { _, mode in
            if let mode, mode != selection { selection = mode }
        }
        .onChange(of: selection) { _, mode in
            if centered != mode { withAnimation(.snappy) { centered = mode } }
        }
        .onAppear {
            DispatchQueue.main.async { centered = selection }
        }
    }
}

/// シャッター。細い輪の中に白い円（動画は赤、録画中は四角になる）
private struct ShutterButton: View {
    let kind: CameraModel.CaptureKind
    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 76, height: 76)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 31, style: .continuous)
                    .fill(kind == .video ? Color.red : Color.white)
                    .frame(width: isRecording ? 28 : 62, height: isRecording ? 28 : 62)
                if isBusy && !isRecording {
                    ProgressView().tint(kind == .video ? .white : .black)
                }
            }
            .animation(.snappy(duration: 0.25), value: isRecording)
            .animation(.snappy(duration: 0.25), value: kind)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(kind == .video ? (isRecording ? "録画を止める" : "録画する") : "シャッター")
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    /// 上の表示などに使う、小さな等幅の文字
    func hudText() -> some View {
        self
            .font(.caption2.weight(.semibold).monospaced())
            .tracking(1.2)
            .lineLimit(1)
    }

    /// プレビューの上に置く、黒い半透明の札
    func hudChip() -> some View {
        self
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// 最後に撮った写真を大きく表示する
private struct PhotoSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("写真", image: Image(uiImage: image)))
                    }
                }
                .navigationTitle("写真アプリに保存しました")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 分割の設定：並べ方と、コマごとのフィルタを選ぶ
private struct ContactSettingsView: View {
    @ObservedObject var camera: CameraModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("並べ方（横×縦）") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                        ForEach(ContactLayout.allCases) { layout in
                            Button {
                                camera.contactLayout = layout
                            } label: {
                                VStack(spacing: 6) {
                                    LayoutIcon(layout: layout, selected: camera.contactLayout == layout)
                                        .frame(width: 40, height: 40)
                                    Text(layout.title)
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(camera.contactLayout == layout
                                                         ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.secondary))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    ForEach(0..<camera.contactLayout.count, id: \.self) { index in
                        Picker(selection: slotBinding(index)) {
                            ForEach(ContactLayout.selectableModes) { mode in
                                Text(mode.title).tag(mode)
                            }
                        } label: {
                            Text(slotName(index))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("コマごとのフィルタ")
                } footer: {
                    Text("左上から右へ、上の段から順に並びます。同じフィルタを何回使ってもかまいません。")
                }

                Section {
                    Toggle("各コマにフィルタ名を入れる", isOn: $camera.contactLabels)
                }
            }
            .navigationTitle("分割の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func slotBinding(_ index: Int) -> Binding<LookMode> {
        Binding(
            get: { camera.contactSlots[index] },
            set: { camera.contactSlots[index] = $0 }
        )
    }

    /// 「1段目・左」のような、コマの場所の名前
    private func slotName(_ index: Int) -> String {
        let layout = camera.contactLayout
        let row = index / layout.columns + 1
        let column = index % layout.columns + 1
        return layout.columns == 1 ? "\(row)段目" : "\(row)段目・\(column)列目"
    }
}

/// 並べ方の小さな絵
private struct LayoutIcon: View {
    let layout: ContactLayout
    let selected: Bool

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let cellW = (geo.size.width - gap * CGFloat(layout.columns - 1)) / CGFloat(layout.columns)
            let cellH = (geo.size.height - gap * CGFloat(layout.rows - 1)) / CGFloat(layout.rows)
            VStack(spacing: gap) {
                ForEach(0..<layout.rows, id: \.self) { _ in
                    HStack(spacing: gap) {
                        ForEach(0..<layout.columns, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                                .frame(width: cellW, height: cellH)
                        }
                    }
                }
            }
        }
    }
}
