import SwiftUI

/// アプリの最初の画面：共有アルバムが主役。カメラは右下のボタンを押したときだけ、全画面で開く。
/// 起動直後はレンズの絞りが開く起動画面を重ねる
struct RootView: View {
    @ObservedObject private var album = AlbumStore.shared
    @State private var showingCamera = false
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            AlbumView(store: album, onOpenCamera: { showingCamera = true })
            if showingSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.4)) { showingSplash = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showingCamera) {
            ContentView()
                .preferredColorScheme(.dark)
        }
        // 招待を受けたときや通知をタップしたとき：カメラを閉じてアルバムに戻る
        .onChange(of: album.showAlbum) { _, show in
            guard show else { return }
            showingCamera = false
            album.showAlbum = false
        }
        // 写真の「このフィルタで撮る」：写真の画面が閉じるのを待ってからカメラを開く（モードはカメラ側で受け取る）
        .onChange(of: album.requestedMode) { _, title in
            guard title != nil, !showingCamera else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showingCamera = true }
        }
    }
}
