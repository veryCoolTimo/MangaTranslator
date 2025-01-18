import Foundation
import AppKit

actor ExportService {
    func selectExportDirectory() async throws -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Выбрать папку"
            panel.message = "Выберите папку для сохранения переведенных страниц"
            
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
    
    func exportPages(_ pages: [MangaPage], to directory: URL) async throws {
        for (index, page) in pages.enumerated() {
            let fileName = String(format: "page_%03d.png", index + 1)
            let fileURL = directory.appendingPathComponent(fileName)
            
            if let processedImage = await page.processedImage {
                try await saveImage(processedImage.image, to: fileURL)
            }
        }
    }
    
    func saveImage(_ image: NSImage, to url: URL) async throws {
        try await Task.detached {
            try image.savePNG(to: url)
        }.value
    }
}

enum ExportError: LocalizedError {
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return message
        }
    }
} 
