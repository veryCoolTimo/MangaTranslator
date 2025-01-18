import SwiftUI

@objc final class ImageContainer: NSObject, @unchecked Sendable {
    let image: NSImage
    
    init(image: NSImage) {
        self.image = image
    }
}

@MainActor
struct ImageWrapper: Sendable {
    private let container: ImageContainer
    
    var image: NSImage {
        container.image
    }
    
    init(_ image: NSImage) {
        self.container = ImageContainer(image: image)
    }
    
    static func wrap(_ image: NSImage) -> ImageWrapper {
        ImageWrapper(image)
    }
} 