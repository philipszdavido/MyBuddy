//
//  ComposePostView.swift
//  MyBuddy
//
//  Full composer: text, up to 10 photos/videos, and who can see the post.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A picked video, copied into the app's temporary directory so it can be uploaded.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SocialFeedViewModel

    @State private var text = ""
    @State private var audience: PostAudience = .contacts
    @State private var selection: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var videos: [URL] = []
    @State private var loadingMedia = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                    Text("\(text.count)/\(SocialFeedViewModel.maxPostLength)")
                        .font(.caption)
                        .foregroundStyle(text.count > SocialFeedViewModel.maxPostLength ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section("Photos & videos") {
                    PhotosPicker(selection: $selection, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                        Label(selection.isEmpty ? "Add photos or videos" : "\(selection.count) selected", systemImage: "photo.on.rectangle")
                    }
                    if loadingMedia { ProgressView() }
                    if !images.isEmpty || !videos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(images.indices, id: \.self) { i in
                                    Image(uiImage: images[i]).resizable().scaledToFill().frame(width: 72, height: 72).clipped().cornerRadius(8)
                                }
                                ForEach(videos, id: \.self) { _ in
                                    ZStack { Color.gray.opacity(0.2); Image(systemName: "video.fill") }.frame(width: 72, height: 72).cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                if model.isPublishing, let progress = model.uploadProgress {
                    Section { UploadProgressView(progress: progress, label: "Uploading") }
                }
                Section {
                    Picker("Who can see this", selection: $audience) {
                        Text("Contacts").tag(PostAudience.contacts)
                        Text("Followers").tag(PostAudience.followers)
                        Text("Everyone").tag(PostAudience.public)
                    }
                } footer: {
                    Text(audienceFooter)
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isPublishing {
                        ProgressView()
                    } else {
                        Button("Post") {
                            Task {
                                if await model.publish(text: text, images: images, videos: videos, audience: audience) { dismiss() }
                            }
                        }
                        .disabled(loadingMedia || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty && videos.isEmpty))
                    }
                }
            }
            .onChange(of: selection) { Task { await loadSelection() } }
            .errorAlert($model.errorMessage)
            .interactiveDismissDisabled(model.isPublishing)
        }
    }

    private var audienceFooter: String {
        switch audience {
        case .contacts: return "Your matched phone contacts can see this post."
        case .followers: return "People who follow you can see this post."
        case .public: return "Anyone on MyBuddy can see this post, and it can be reposted."
        }
    }

    private func loadSelection() async {
        loadingMedia = true
        defer { loadingMedia = false }
        var newImages: [UIImage] = []
        var newVideos: [URL] = []
        for item in selection {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let movie = try? await item.loadTransferable(type: PickedMovie.self) { newVideos.append(movie.url) }
            } else if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                newImages.append(image) // HEIC is decoded here and re-encoded as JPEG before upload
            }
        }
        images = newImages
        videos = newVideos
    }
}
