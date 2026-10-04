import CloudKit
import SwiftUI

/// 共有アルバムの画面：アルバムの切り替え、友だちの招待、写真の一覧
struct AlbumView: View {
    @ObservedObject var store: AlbumStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened: AlbumPhoto?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.albums.count > 1 {
                        Picker("アルバム", selection: $store.selectedID) {
                            ForEach(store.albums) { album in
                                Text(album.title).tag(Optional(album.id))
                            }
                        }
                        .pickerStyle(.menu)
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
                        ShareLink(item: AlbumInvitation(),
                                  preview: SharePreview("フィルムカメラの共有アルバム")) {
                            Label("友だちを招待", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
            }
            .task { await store.refresh() }
            .sheet(item: $opened) { photo in
                AlbumPhotoView(store: store, photo: photo)
            }
        }
    }
}

/// 招待の共有シートに渡すもの（自分のアルバムの CKShare を用意して渡す）
struct AlbumInvitation: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { _ in
            .prepareShare(container: AlbumStore.container) {
                try await AlbumStore.prepareShare()
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
