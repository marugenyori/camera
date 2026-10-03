import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashOpacity = 0.0
    @State private var showingPhoto = false
    @AppStorage("showGrid") private var showGrid = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .bottom) {
                    preview
                    VStack(spacing: 10) {
                        if camera.mode == .double && camera.captureKind == .photo { exposureOptions }
                        zoomBar
                    }
                    .padding(.bottom, 14)
                }
                modePicker
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
        // ズーム中は 0.1× ごとにカチカチと手応えを返す（ズームリングの目盛りのように）
        .sensoryFeedback(.selection, trigger: Int((camera.zoom * 10).rounded()))
        .sheet(isPresented: $showingPhoto) {
            if let photo = camera.lastPhoto {
                PhotoSheet(image: photo)
            }
        }
    }

    // MARK: - 上のバー

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemImage: camera.dateStamp ? "calendar.badge.checkmark" : "calendar",
                            isOn: camera.dateStamp, label: "日付") {
                camera.dateStamp.toggle()
            }
            GlassIconButton(systemImage: "squareshape.split.3x3", isOn: showGrid, label: "グリッド") {
                showGrid.toggle()
            }
            Spacer()
            statusChip
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusChip: some View {
        if camera.isRecording, let start = camera.recordingStartedAt {
            TimelineView(.periodic(from: start, by: 0.5)) { context in
                let seconds = Int(context.date.timeIntervalSince(start))
                Label(String(format: "%02d:%02d", seconds / 60, seconds % 60), systemImage: "circle.fill")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.red, in: Capsule())
            }
        } else if camera.mode == .double && !camera.exposures.isEmpty && !camera.isBursting {
            Button {
                camera.discardExposures()
            } label: {
                Label("\(camera.exposures.count) / \(camera.exposureCount) ・ 撮り直す",
                      systemImage: "arrow.uturn.backward")
                    .chipStyle()
            }
        } else if camera.mode.usesDepth && camera.isDepthActive {
            Label("距離で光を調整", systemImage: "dot.radiowaves.left.and.right")
                .chipStyle(tinted: true)
        } else {
            Text(camera.mode.caption)
                .chipStyle()
        }
    }

    // MARK: - プレビュー

    private var preview: some View {
        CameraPreview(model: camera)
            .overlay {
                if showGrid { GridOverlay() }
            }
            .overlay { statusOverlay }
            .overlay(alignment: .top) {
                if let message = camera.message {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
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
                guard !camera.isRecording else { return }
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

    /// 押している間ズームし続けるレバー（W / T）と、0.5× / 1× / 2× のボタン
    private var zoomBar: some View {
        HStack(spacing: 4) {
            ZoomLever(title: "W") { camera.zoomLever($0 ? -1 : 0) }
            ForEach(zoomPresets, id: \.self) { preset in
                let active = activePreset == preset
                Button {
                    camera.zoom(to: preset)
                } label: {
                    Text(active ? Self.zoomLabel(camera.zoom) + "×" : Self.zoomLabel(preset))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(active ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white))
                        .frame(width: active ? 46 : 34, height: 34)
                        .background(Capsule().fill(Color.black.opacity(active ? 0.55 : 0.3)))
                }
            }
            ZoomLever(title: "T") { camera.zoomLever($0 ? 1 : 0) }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.snappy, value: activePreset)
    }

    private var zoomPresets: [CGFloat] {
        [0.5, 1, 2].filter { camera.zoomRange.contains($0) || abs($0 - camera.zoomRange.lowerBound) < 0.02 }
    }

    /// 今の倍率がどのボタンの範囲にあるか（そのボタンに今の倍率を出す）
    private var activePreset: CGFloat? {
        zoomPresets.last { camera.zoom >= $0 - 0.02 }
    }

    private static func zoomLabel(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() && rounded >= 1
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }

    // MARK: - モード選択

    private var modePicker: some View {
        // モードが多いので横にスクロールでき、選んだものが中央に来る
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(LookMode.allCases) { mode in
                        let selected = camera.mode == mode
                        Button {
                            withAnimation(.snappy) { camera.mode = mode }
                        } label: {
                            VStack(spacing: 5) {
                                Text(mode.title)
                                    .font(.subheadline.weight(selected ? .bold : .medium))
                                    .foregroundStyle(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.6)))
                                Circle()
                                    .fill(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.clear))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .id(mode)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: camera.mode) { _, mode in
                withAnimation(.snappy) { proxy.scrollTo(mode, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(camera.mode, anchor: .center) }
        }
        .disabled(camera.isRecording)
        .padding(.top, 14)
    }

    private var kindPicker: some View {
        HStack(spacing: 28) {
            kindButton("写真", kind: .photo)
            kindButton("ビデオ", kind: .video)
        }
        .disabled(camera.isRecording || camera.isSaving)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func kindButton(_ title: String, kind: CameraModel.CaptureKind) -> some View {
        let selected = camera.captureKind == kind
        return Button {
            withAnimation(.snappy) { camera.captureKind = kind }
        } label: {
            Text(title)
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
    }

    // MARK: - 多重露光の設定

    private var exposureOptions: some View {
        HStack(spacing: 10) {
            Picker("枚数", selection: $camera.exposureCount) {
                ForEach(2...4, id: \.self) { Text("\($0)枚").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Menu {
                Picker("撮り方", selection: $camera.burstInterval) {
                    ForEach(CameraModel.burstIntervals, id: \.self) { interval in
                        Text(Self.burstLabel(interval)).tag(interval)
                    }
                }
            } label: {
                Label(Self.burstLabel(camera.burstInterval), systemImage: "timer")
                    .chipStyle()
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
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
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .disabled(camera.status != .running || camera.isRecording)
            .accessibilityLabel("カメラを切り替え")
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }
}

// MARK: - 部品

/// すりガラス風の丸いアイコンボタン（オンのときはテーマ色で塗る）
private struct GlassIconButton: View {
    let systemImage: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 40, height: 40)
                .background {
                    if isOn {
                        Circle().fill(.tint)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
        .accessibilityLabel(label)
    }
}

/// 押している間だけ動くズームレバー（離すと止まる）
private struct ZoomLever: View {
    let title: String
    let onPress: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .foregroundStyle(pressed ? Color.black : Color.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(pressed ? Color.white : Color.white.opacity(0.12)))
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

/// シャッター。写真は白、動画は赤（録画中は四角になる）
private struct ShutterButton: View {
    let kind: CameraModel.CaptureKind
    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 32, style: .continuous)
                    .fill(kind == .video ? Color.red : Color.white)
                    .frame(width: isRecording ? 32 : 64, height: isRecording ? 32 : 64)
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
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    /// 上のバーなどに置く、すりガラス風の小さな札
    func chipStyle(tinted: Bool = false) -> some View {
        self
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tinted ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.85)))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
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

/// 三分割のグリッド。プレビューの写真（縦 4:3）が映っている範囲に合わせて線を引く
private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let aspect: CGFloat = 3.0 / 4.0
            let width = min(geo.size.width, geo.size.height * aspect)
            let height = width / aspect
            let rect = CGRect(x: (geo.size.width - width) / 2, y: (geo.size.height - height) / 2,
                              width: width, height: height)
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
            .stroke(Color.white.opacity(0.45), lineWidth: 0.7)
            .shadow(color: .black.opacity(0.4), radius: 0.5)
        }
        .allowsHitTesting(false)
    }
}
