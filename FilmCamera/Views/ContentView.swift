import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashOpacity = 0.0
    @State private var showingPhoto = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                preview
                modePicker
                controls
            }

            // フラッシュモードで撮ったときに画面を白く光らせる
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
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
        .sheet(isPresented: $showingPhoto) {
            if let photo = camera.lastPhoto {
                PhotoSheet(image: photo)
            }
        }
    }

    // MARK: - 上のバー

    private var topBar: some View {
        HStack {
            Button {
                camera.dateStamp.toggle()
            } label: {
                Label("日付", systemImage: camera.dateStamp ? "calendar.badge.checkmark" : "calendar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(camera.dateStamp ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.15)),
                                in: Capsule())
                    .foregroundStyle(camera.dateStamp ? .black : .white)
            }
            Spacer()
            if camera.mode == .double && camera.firstExposure != nil {
                Button {
                    camera.discardFirstExposure()
                } label: {
                    Label("1枚目を撮り直す", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .tint(.white)
            } else if camera.mode.usesDepth && camera.isDepthActive {
                Label("距離を測って光を当てています", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Text(camera.mode.caption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - プレビュー

    private var preview: some View {
        CameraPreview(model: camera)
            .overlay { statusOverlay }
            .overlay(alignment: .top) {
                if let message = camera.message {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height) else { return }
                    shiftMode(by: dx < 0 ? 1 : -1)
                }
            )
            .onTapGesture(count: 2) { camera.switchCamera() }
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

    // MARK: - モード選択

    private var modePicker: some View {
        // モードが増えて 1 行に収まらないので、横にスクロールできるようにし、選んだものを中央に寄せる
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(LookMode.allCases) { mode in
                        Button {
                            withAnimation(.snappy) { camera.mode = mode }
                        } label: {
                            Text(mode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(camera.mode == mode ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.white.opacity(0.75)))
                        }
                        .id(mode)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: camera.mode) { _, mode in
                withAnimation(.snappy) { proxy.scrollTo(mode, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(camera.mode, anchor: .center) }
        }
        .padding(.vertical, 14)
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
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.4)))
            }
            .disabled(camera.lastPhoto == nil)
            .accessibilityLabel("最後に撮った写真")

            Spacer()

            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 62, height: 62)
                    if camera.isSaving {
                        ProgressView().tint(.black)
                    }
                }
            }
            .disabled(camera.status != .running || camera.isSaving)
            .accessibilityLabel("シャッター")

            Spacer()

            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .disabled(camera.status != .running)
            .accessibilityLabel("カメラを切り替え")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
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
