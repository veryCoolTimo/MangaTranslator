import SwiftUI

struct ResultView: View {
    let page: MangaPage
    
    var body: some View {
        VStack(spacing: 20) {
            if let processedImage = page.processedImage {
                Image(nsImage: processedImage.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: .infinity)
                
                Button("Сохранить результат") {
                    saveProcessedImage()
                }
                .buttonStyle(.borderedProminent)
            } else if page.isProcessing {
                ProgressView("Обработка изображения...")
                    .scaleEffect(1.5)
            } else if let error = page.error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Ошибка обработки")
                        .font(.title2)
                    Text(error)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Выберите изображение для просмотра результата")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func saveProcessedImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "translated_page.png"
        
        if savePanel.runModal() == .OK {
            guard let url = savePanel.url,
                  let processedImage = page.processedImage?.image,
                  let imageData = processedImage.pngData else { return }
            
            try? imageData.write(to: url)
        }
    }
} 