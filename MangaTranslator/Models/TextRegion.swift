import Foundation
import CoreGraphics

struct TextRegion {
    let rect: CGRect
    let originalText: String
    var translatedText: String?
}

struct Translation {
    let originalText: String
    let translatedText: String
    let confidence: Double
}

enum ProcessingStatus {
    case pending
    case processing
    case completed
    case error(String)
} 