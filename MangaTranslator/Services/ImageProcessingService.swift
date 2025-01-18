import Foundation
import Vision
import CoreImage
import AppKit
import SwiftUI

// MARK: - Image Processing Service

actor ImageProcessingService {
    private let inpaintingService: InpaintingService
    private let translationService: TranslationService
    
    init() async throws {
        self.inpaintingService = InpaintingService()
        self.translationService = try await TranslationService()
    }
    
    // MARK: - Text Recognition
    
    func recognizeText(in wrapper: ImageWrapper) async throws -> [TextRegion] {
        guard let cgImage = await wrapper.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }
        
        // Предварительная обработка изображения для улучшения распознавания
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        // Применяем фильтры для улучшения контраста и четкости
        let filters = [
            "CIColorControls": [
                kCIInputContrastKey: 1.1,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0
            ],
            "CIUnsharpMask": [
                kCIInputRadiusKey: 1.0,
                kCIInputIntensityKey: 0.5
            ]
        ]
        
        var processedImage = ciImage
        for (filterName, params) in filters {
            guard let filter = CIFilter(name: filterName) else { continue }
            filter.setDefaults()
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            
            for (key, value) in params {
                filter.setValue(value, forKey: key)
            }
            
            if let outputImage = filter.outputImage {
                processedImage = outputImage
            }
        }
        
        guard let processedCGImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            throw ImageProcessingError.processingFailed("Не удалось обработать изображение")
        }
        
        // Настраиваем распознавание текста
        let requestHandler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ko", "ja"]  // Добавляем японский для лучшего распознавания иероглифов
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.customWords = ["の", "は", "が", "を", "に", "へ", "で", "と", "も", "や"]  // Добавляем частые японские частицы
        request.minimumTextHeight = 0.01  // Уменьшаем минимальную высоту текста
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try requestHandler.perform([request])
                guard let observations = request.results else {
                    continuation.resume(returning: [])
                    return
                }
                
                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                var regions: [TextRegion] = []
                
                // Фильтруем и объединяем близкие регионы
                let sortedObservations = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                
                for observation in sortedObservations {
                    guard let recognizedText = observation.topCandidates(1).first?.string,
                          !recognizedText.trimmingCharacters(in: .whitespaces).isEmpty else {
                        continue
                    }
                    
                    let boundingBox = observation.boundingBox
                    let rect = CGRect(
                        x: boundingBox.origin.x * imageSize.width,
                        y: boundingBox.origin.y * imageSize.height,
                        width: boundingBox.width * imageSize.width,
                        height: boundingBox.height * imageSize.height
                    )
                    
                    // Проверяем, можно ли объединить с предыдущим регионом
                    if let lastRegion = regions.last,
                       abs(lastRegion.rect.midY - rect.midY) < rect.height * 0.5 &&
                       abs(lastRegion.rect.maxX - rect.minX) < rect.width * 2.0 {
                        // Объединяем регионы
                        let unionRect = lastRegion.rect.union(rect)
                        let combinedText = lastRegion.originalText + " " + recognizedText
                        regions[regions.count - 1] = TextRegion(
                            rect: unionRect,
                            originalText: combinedText,
                            translatedText: nil
                        )
                    } else {
                        // Добавляем новый регион
                        regions.append(TextRegion(
                            rect: rect,
                            originalText: recognizedText,
                            translatedText: nil
                        ))
                    }
                }
                
                continuation.resume(returning: regions)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Translation
    
    func translateRegions(_ regions: [TextRegion], to targetLanguage: String) async throws -> [TextRegion] {
        let texts = regions.map { region in region.originalText }
        let translations = try await translationService.translateBatch(texts, from: "Korean", to: targetLanguage)
        
        return regions.enumerated().map { index, region in
            var newRegion = region
            newRegion.translatedText = translations[index].translatedText
            return newRegion
        }
    }
    
    // MARK: - Image Inpainting
    
    func inpaintTextRegions(wrapper: ImageWrapper, regions: [TextRegion]) async throws -> ImageWrapper {
        guard let cgImage = await wrapper.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }
        
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let resultImage = NSImage(size: size)
        
        await resultImage.lockFocus()
        
        // Отрисовываем исходное изображение
        await wrapper.image.draw(in: NSRect(origin: .zero, size: size))
        
        // Получаем контекст для рисования
        guard let context = NSGraphicsContext.current?.cgContext else {
            throw ImageProcessingError.processingFailed("Не удалось получить контекст рисования")
        }
        
        for region in regions {
            print("🎨 Заливка области: x=\(region.rect.origin.x), y=\(region.rect.origin.y), width=\(region.rect.width), height=\(region.rect.height)")
            
            // Сохраняем состояние контекста
            context.saveGState()
            
            // Создаем маску для области текста
            context.addRect(region.rect)
            context.clip()
            
            // Заливаем белым цветом
            context.setFillColor(NSColor.white.cgColor)
            context.fill(region.rect)
            
            // Восстанавливаем состояние контекста
            context.restoreGState()
        }
        
        await resultImage.unlockFocus()
        return await ImageWrapper.wrap(resultImage)
    }
    
    private func getBackgroundBrightness(for textRect: CGRect, around expandedRect: CGRect, in image: NSImage) async -> CGFloat {
        guard let cgImage = await image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0.5 }
        
        // Создаем контекст для анализа цвета
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                    width: Int(expandedRect.width),
                                    height: Int(expandedRect.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo) else { return 0.5 }
        
        // Рисуем часть изображения в контекст
        let drawRect = CGRect(origin: .zero, size: expandedRect.size)
        context.draw(cgImage, in: drawRect)
        
        // Анализируем пиксели
        guard let data = context.data else { return 0.5 }
        let pointer = data.bindMemory(to: UInt8.self, capacity: Int(expandedRect.width * expandedRect.height * 4))
        
        var sumR: Int = 0, sumG: Int = 0, sumB: Int = 0, count: Int = 0
        let bytesPerRow = context.bytesPerRow
        let bytesPerPixel = 4
        
        // Анализируем пиксели в области текста
        for y in 0..<Int(textRect.height) {
            for x in 0..<Int(textRect.width) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                sumR += Int(pointer[offset])
                sumG += Int(pointer[offset + 1])
                sumB += Int(pointer[offset + 2])
                count += 1
            }
        }
        
        guard count > 0 else { return 0.5 }
        
        // Вычисляем средний цвет
        let avgR = CGFloat(sumR) / CGFloat(count) / 255.0
        let avgG = CGFloat(sumG) / CGFloat(count) / 255.0
        let avgB = CGFloat(sumB) / CGFloat(count) / 255.0
        
        // Вычисляем яркость (используя формулу относительной яркости)
        let brightness = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB)
        
        print("🎨 Анализ цвета фона: яркость = \(brightness)")
        return brightness
    }
    
    // MARK: - Text Overlay
    
    func overlayTranslatedText(wrapper: ImageWrapper, regions: [TextRegion], targetLanguage: String) async throws -> ImageWrapper {
        guard let cgImage = await wrapper.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }
        
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let resultImage = NSImage(size: size)
        
        await resultImage.lockFocus()
        
        // Отрисовываем исходное изображение
        await wrapper.image.draw(in: NSRect(origin: .zero, size: size))
        
        // Получаем контекст для рисования
        guard let context = NSGraphicsContext.current?.cgContext else {
            throw ImageProcessingError.processingFailed("Не удалось получить контекст рисования")
        }
        
        for region in regions {
            guard let translatedText = region.translatedText else { continue }
            
            print("📝 Отрисовка текста в области: x=\(region.rect.origin.x), y=\(region.rect.origin.y), width=\(region.rect.width), height=\(region.rect.height)")
            
            // Анализируем цвет фона
            let expandedRect = region.rect.insetBy(dx: -5, dy: -5)
            let brightness = await getBackgroundBrightness(for: region.rect, around: expandedRect, in: wrapper.image)
            
            // Выбираем цвет текста на основе яркости фона
            let (textColor, strokeColor) = brightness > 0.5 
                ? (NSColor.black, NSColor.white)  // Для светлого фона
                : (NSColor.white, NSColor.black)  // Для темного фона
            
            print("📝 Яркость фона: \(brightness), выбран цвет текста: \(brightness > 0.5 ? "черный" : "белый")")
            
            // Сохраняем состояние контекста
            context.saveGState()
            
            // Создаем параграф стиль для центрирования текста
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            // Настраиваем размер шрифта в зависимости от размера области
            let maxWidth = region.rect.width * 2.0  // Максимальная ширина текста
            let maxHeight = region.rect.height * 1.5  // Максимальная высота текста
            let fontSize = min(region.rect.height * 0.8, region.rect.width * 0.2)  // Адаптивный размер шрифта
            
            // Создаем атрибуты для текста
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .strokeColor: strokeColor,
                .strokeWidth: -2.0,
                .paragraphStyle: paragraphStyle
            ]
            
            // Создаем атрибутированную строку
            let attributedString = NSAttributedString(string: translatedText, attributes: attributes)
            
            // Получаем размер текста
            let textSize = attributedString.size()
            
            // Вычисляем позицию текста с учетом размеров области
            let verticalOffset = max(region.rect.height * 1.5, 50.0)  // Минимальный отступ 50 пикселей
            let horizontalOffset = region.rect.width * 0.3  // Смещение вправо на 30% ширины
            
            let x = region.rect.origin.x + horizontalOffset
            let y = size.height - region.rect.origin.y + verticalOffset
            
            // Создаем прямоугольник для отрисовки текста
            let textRect = NSRect(
                x: x,
                y: y,
                width: maxWidth,
                height: maxHeight
            )
            
            // Рисуем текст в прямоугольнике
            attributedString.draw(in: textRect)
            
            // Восстанавливаем состояние контекста
            context.restoreGState()
        }
        
        await resultImage.unlockFocus()
        return await ImageWrapper.wrap(resultImage)
    }
}

// MARK: - Errors

enum ImageProcessingError: LocalizedError {
    case invalidImage
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Не удалось обработать изображение"
        case .processingFailed(let message):
            return "Ошибка обработки: \(message)"
        }
    }
} 