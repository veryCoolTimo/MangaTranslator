import Foundation
import SwiftUI

actor MangaPage: Identifiable {
    let id = UUID()
    let originalImage: ImageWrapper
    var processedImage: ImageWrapper?
    var textRegions: [TextRegion] = []
    var isProcessing: Bool = false
    var error: String?
    
    init(originalImage: ImageWrapper) {
        self.originalImage = originalImage
    }
    
    func setProcessing(_ value: Bool) {
        isProcessing = value
    }
    
    func setError(_ value: String?) {
        error = value
    }
    
    func setTextRegions(_ value: [TextRegion]) {
        textRegions = value
    }
    
    func setProcessedImage(_ value: ImageWrapper?) {
        processedImage = value
    }
    
    func getPreviewImage() async -> NSImage {
        if let processedImage = processedImage {
            return await processedImage.image
        }
        return await originalImage.image
    }
    
    func getIsProcessing() async -> Bool {
        return isProcessing
    }
    
    func getError() async -> String? {
        return error
    }
}

@MainActor
class PagePreviewState: ObservableObject {
    @Published var displayedImage: NSImage?
    @Published var isProcessing: Bool = false
    @Published var error: String?
    private var updateTask: Task<Void, Never>?
    
    func startUpdating(from page: MangaPage) {
        updateTask?.cancel()
        updateTask = Task {
            while !Task.isCancelled {
                await update(from: page)
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 секунды
            }
        }
    }
    
    func stopUpdating() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    private func update(from page: MangaPage) async {
        do {
            let image = await page.getPreviewImage()
            let processing = await page.getIsProcessing()
            let currentError = await page.getError()
            
            await MainActor.run {
                self.displayedImage = image
                self.isProcessing = processing
                self.error = currentError
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}

struct PagePreview: View {
    let page: MangaPage
    @StateObject private var state = PagePreviewState()
    
    var preview: some View {
        Group {
            if let image = state.displayedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
    }
    
    var body: some View {
        preview
            .onAppear {
                state.startUpdating(from: page)
            }
            .onDisappear {
                state.stopUpdating()
            }
    }
} 
