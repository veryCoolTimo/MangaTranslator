import AppKit

extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    func savePNG(to url: URL) throws {
        guard let data = pngData else {
            throw ImageError.conversionFailed
        }
        try data.write(to: url)
    }
}

enum ImageError: Error {
    case conversionFailed
} 


