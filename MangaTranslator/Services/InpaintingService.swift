import Foundation
import CoreImage
import AppKit

class InpaintingService {
    private let context: CIContext
    private let ciContext: CIContext
    
    init() {
        self.context = CIContext()
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    func inpaint(image: NSImage, regions: [TextRegion]) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        
        // Создаем маску для областей с текстом
        let maskImage = createMask(for: regions, size: CGSize(width: cgImage.width, height: cgImage.height))
        
        // Применяем улучшенный алгоритм inpainting
        guard let outputImage = applyAdvancedInpainting(to: inputImage, mask: maskImage) else {
            throw ImageProcessingError.processingFailed("Не удалось применить фильтр inpainting")
        }
        
        // Конвертируем обратно в NSImage
        guard let resultCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageProcessingError.processingFailed("Не удалось создать финальное изображение")
        }
        
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let resultImage = NSImage(size: size)
        resultImage.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            resultImage.unlockFocus()
            throw ImageProcessingError.processingFailed("Не удалось получить графический контекст")
        }
        
        context.draw(resultCGImage, in: CGRect(origin: .zero, size: size))
        resultImage.unlockFocus()
        
        return resultImage
    }
    
    private func createMask(for regions: [TextRegion], size: CGSize) -> CIImage {
        let maskImage = NSImage(size: size)
        maskImage.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            maskImage.unlockFocus()
            return CIImage.empty()
        }
        
        // Заполняем черным (фон)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Рисуем белые области для текста с мягкими краями
        context.setFillColor(NSColor.white.cgColor)
        for region in regions {
            // Добавляем больший отступ для лучшего результата
            let expandedRect = region.rect.insetBy(dx: -4, dy: -4)
            
            // Создаем путь с закругленными углами
            let path = NSBezierPath(roundedRect: expandedRect, xRadius: 2, yRadius: 2)
            context.addPath(path.cgPath)
            context.fillPath()
        }
        
        maskImage.unlockFocus()
        
        guard let cgImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return CIImage.empty()
        }
        
        // Применяем размытие к маске для создания мягких краев
        let ciImage = CIImage(cgImage: cgImage)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return ciImage
        }
        
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(2.0, forKey: kCIInputRadiusKey)
        
        return blurFilter.outputImage ?? ciImage
    }
    
    private func applyAdvancedInpainting(to image: CIImage, mask: CIImage) -> CIImage? {
        // 1. Создаем несколько уровней размытия для разных масштабов
        let blurLevels: [(radius: Float, weight: Float)] = [
            (5, 0.5),   // Мелкие детали
            (10, 0.3),  // Средние детали
            (20, 0.2)   // Крупные области
        ]
        
        var blurredImages: [CIImage] = []
        
        for (radius, _) in blurLevels {
            guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { continue }
            blurFilter.setValue(image, forKey: kCIInputImageKey)
            blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
            
            if let blurredImage = blurFilter.outputImage {
                blurredImages.append(blurredImage)
            }
        }
        
        // 2. Комбинируем размытые изображения с разными весами
        guard var resultImage = blurredImages.first else { return nil }
        
        for i in 1..<blurredImages.count {
            guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { continue }
            blendFilter.setValue(blurredImages[i], forKey: kCIInputImageKey)
            blendFilter.setValue(resultImage, forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
            
            if let blendedImage = blendFilter.outputImage {
                resultImage = blendedImage
            }
        }
        
        // 3. Применяем финальное смешивание с оригинальным изображением
        guard let finalBlendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        finalBlendFilter.setValue(image, forKey: kCIInputImageKey)
        finalBlendFilter.setValue(resultImage, forKey: kCIInputBackgroundImageKey)
        finalBlendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        
        return finalBlendFilter.outputImage
    }
} 