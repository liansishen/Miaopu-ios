import Photos
import SwiftUI

struct CommentImageViewer: View {
    let url: URL

    @State private var saving = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    ContentUnavailableView("图片加载失败", systemImage: "photo")
                @unknown default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("查看图片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(saving ? "正在保存" : "保存图片", systemImage: "square.and.arrow.down") {
                Task { await saveImage() }
            }
            .disabled(saving)
        }
        .alert("图片", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func saveImage() async {
        saving = true
        defer { saving = false }
        do {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                alertMessage = "请在系统设置中允许保存图片到相册。"
                showingAlert = true
                return
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true,
                  data.count <= 20_000_000,
                  let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: error ?? URLError(.cannotWriteToFile)) }
                }
            }
            alertMessage = "已保存到相册"
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
        }
        showingAlert = true
    }
}
