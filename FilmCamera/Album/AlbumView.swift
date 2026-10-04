import CloudKit
import SwiftUI

/// 共有アルバムの画面：アルバムの切り替え、友だちの招待、写真の一覧
struct AlbumView: View {
    @ObservedObject var store: AlbumStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened: AlbumPhoto?
    @State private var showingNewAlbum = false
    @State private var newAlbumName = ""
    @State private var confirmingRemove = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // アルバムの切り替え（友だちのグループごとにアルバムを分けられる）
                    HStack {
                        Picker("アルバム", selection: Binding(
                            get: { store.selected?.id },
                            set: { store.selectedID = $0 }
                        )) {
                            ForEach(store.albums) { album in
                                Label(album.title, systemImage: album.isOwner ? "person.2" : "person.crop.circle")
                                    .tag(Optional(album.id))
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Menu {
                            Button {
                                newAlbumName = ""
                                showingNewAlbum = true
                            } label: {
                                Label("新しいアルバム（グループ）", systemImage: "plus.rectangle.on.rectangle")
                            }
                            if let album = store.selected,
                               !album.isOwner || album.zoneID.zoneName != AlbumStore.ownZoneID.zoneName {
                                Button(role: .destructive) {
                                    confirmingRemove = true
                                } label: {
                                    Label(album.isOwner ? "このアルバムを削除" : "このアルバムから抜ける",
                                          systemImage: album.isOwner ? "trash" : "rectangle.portrait.and.arrow.right")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .accessibilityLabel("アルバムの操作")
                    }

                    Toggle("撮った写真を自動でこのアルバムに入れる", isOn: $store.autoAdd)
                        .font(.subheadline)

                    if let status = store.status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if store.uploading > 0 {
                        Label("\(store.uploading) 枚を送っています", systemImage: "icloud.and.arrow.up")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if store.photos.isEmpty && !store.isLoading && store.status == nil {
                        Text(store.selected?.isOwner == true
                             ? "まだ写真がありません。撮った写真は、写真を開いて「共有アルバムに追加」か、上の自動の設定で入ります。右上から友だちを招待できます。"
                             : "まだ写真がありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(store.photos) { photo in
                            Button {
                                opened = photo
                            } label: {
                                Color.gray.opacity(0.2)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        if let thumbnail = photo.thumbnail {
                                            Image(uiImage: thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                        }
                                    }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .overlay {
                if store.isLoading && store.photos.isEmpty { ProgressView() }
            }
            .refreshable { await store.refresh() }
            .navigationTitle(store.selected?.title ?? "共有アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if store.selected?.isOwner ?? true {
                    ToolbarItem(placement: .primaryAction) {
                        if let url = store.share?.url {
                            // 招待のリンクを、LINE やメッセージなど好きなアプリで送る
                            ShareLink(item: url,
                                      subject: Text("フィルムカメラの共有アルバム"),
                                      message: Text("フィルムカメラの共有アルバムに招待します。リンクを開くと参加できます。")) {
                                Label("招待を送る", systemImage: "paperplane")
                            }
                        } else if store.isPreparingShare {
                            ProgressView()
                        } else {
                            Button {
                                Task { await store.makeShare() }
                            } label: {
                                Label("友だちを招待", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    }
                }
            }
            .task { await store.refresh() }
            .alert("新しいアルバム", isPresented: $showingNewAlbum) {
                TextField("名前（例：家族、サークル）", text: $newAlbumName)
                Button("作る") {
                    let name = newAlbumName
                    Task { await store.createAlbum(named: name) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("グループごとにアルバムを作ると、それぞれ別の友だちを招待できます。")
            }
            .confirmationDialog(store.selected?.isOwner == true
                                ? "このアルバムを削除しますか？" : "このアルバムから抜けますか？",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button(store.selected?.isOwner == true ? "削除する" : "抜ける", role: .destructive) {
                    Task { await store.removeSelectedAlbum() }
                }
            } message: {
                Text(store.selected?.isOwner == true
                     ? "アルバムの写真はすべて消え、招待した人も見られなくなります。"
                     : "このアルバムが一覧から消えます。もう一度入るには招待のリンクが必要です。")
            }
            .sheet(item: $opened) { photo in
                AlbumPhotoView(store: store, photo: photo)
            }
        }
    }
}

/// 共有アルバムの 1 枚を大きく見る
private struct AlbumPhotoView: View {
    @ObservedObject var store: AlbumStore
    let photo: AlbumPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var full: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = full ?? photo.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                if full == nil { ProgressView().tint(.white) }
            }
            .navigationTitle(photo.takenAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if let image = full {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("写真", image: Image(uiImage: image)))
                    }
                }
            }
            .task { full = await store.fullImage(of: photo) }
        }
    }
}
