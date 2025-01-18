import SwiftUI

extension MangaPage {
    var statusText: String {
        if isProcessing {
            return "Обработка..."
        } else if processedImage != nil {
            return "Готово"
        } else if let error = error {
            return "Ошибка: \(error)"
        } else {
            return "Ожидание"
        }
    }
    
    var statusColor: Color {
        if isProcessing {
            return .blue
        } else if processedImage != nil {
            return .green
        } else if error != nil {
            return .red
        } else {
            return .primary
        }
    }
} 