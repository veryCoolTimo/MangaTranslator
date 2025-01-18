import Foundation
import SwiftUI

@MainActor
class MangaTranslatorViewModel: ObservableObject {
    @Published var mangaPages: [MangaPage] = []
    @Published var isProcessing = false
    @Published var currentError: String?
    @Published var exportProgress: Double?
    @Published var selectedPageId: UUID?
    
    var selectedPage: MangaPage? {
        mangaPages.first { $0.id == selectedPageId }
    }
    
    // Настройки
    @Published var targetLanguage = "Russian"
    
    private var imageProcessor: ImageProcessingService?
    private let exportService = ExportService()
    
    init() {
        print("Инициализация MangaTranslatorViewModel")
        self.imageProcessor = nil
        
        Task {
            do {
                self.imageProcessor = try await ImageProcessingService()
                print("ImageProcessingService успешно инициализирован")
            } catch TranslationError.missingAPIKey {
                print("Ошибка: отсутствует API ключ")
                await MainActor.run {
                    self.currentError = "Отсутствует API ключ OpenAI. Пожалуйста, добавьте ключ в файл .env или установите переменную окружения OPENAI_API_KEY"
                }
            } catch {
                print("Ошибка при инициализации: \(error.localizedDescription)")
                await MainActor.run {
                    self.currentError = error.localizedDescription
                }
            }
        }
    }
    
    // Экспорт страниц
    func exportPages() async {
        guard !mangaPages.isEmpty else {
            currentError = "Нет страниц для экспорта"
            return
        }
        
        do {
            if let directory = try await exportService.selectExportDirectory() {
                isProcessing = true
                exportProgress = 0.0
                
                try await exportService.exportPages(mangaPages, to: directory)
                
                exportProgress = nil
                isProcessing = false
            }
        } catch {
            currentError = error.localizedDescription
            exportProgress = nil
            isProcessing = false
        }
    }
    
    // Добавление новой страницы
    func addPage(image: NSImage) {
        print("Добавление новой страницы")
        let wrappedImage = ImageWrapper(image)
        let page = MangaPage(originalImage: wrappedImage)
        mangaPages.append(page)
        
        Task {
            await processPage(at: mangaPages.count - 1)
        }
    }
    
    // Удаление страницы
    func removePage(at index: Int) {
        guard index < mangaPages.count else { return }
        mangaPages.remove(at: index)
    }
    
    // Очистка всех страниц
    func clearPages() {
        mangaPages.removeAll()
    }
    
    // Обработка страницы
    private func processPage(at index: Int) async {
        guard let processor = imageProcessor else {
            currentError = "Сервис обработки изображений не инициализирован"
            return
        }
        guard index >= 0 && index < mangaPages.count else { return }
        
        print("Начало обработки страницы \(index)")
        await mangaPages[index].setProcessing(true)
        
        do {
            let wrappedOriginalImage = mangaPages[index].originalImage
            
            // 1. Распознавание текста
            print("1. Распознавание текста")
            let regions = try await processor.recognizeText(in: wrappedOriginalImage)
            await mangaPages[index].setTextRegions(regions)
            print("Найдено регионов с текстом: \(regions.count)")
            
            // 2. Перевод текста
            print("2. Перевод текста")
            let translatedRegions = try await processor.translateRegions(regions, to: targetLanguage)
            print("Сохранение переводов")
            await mangaPages[index].setTextRegions(translatedRegions)
            
            // 3. Закрашивание текста
            print("3. Закрашивание текста")
            let inpaintedImage = try await processor.inpaintTextRegions(
                wrapper: wrappedOriginalImage,
                regions: translatedRegions
            )
            print("Закрашивание успешно")
            
            // 4. Наложение текста
            print("4. Наложение текста")
            let finalImage = try await processor.overlayTranslatedText(
                wrapper: inpaintedImage,
                regions: translatedRegions,
                targetLanguage: targetLanguage
            )
            print("Наложение текста успешно")
            
            // Сохраняем результат
            await mangaPages[index].setProcessedImage(finalImage)
            await mangaPages[index].setProcessing(false)
            print("Обработка страницы завершена")
            
        } catch {
            print("Ошибка при обработке: \(error.localizedDescription)")
            await mangaPages[index].setError(error.localizedDescription)
            await mangaPages[index].setProcessing(false)
        }
    }
    
    enum ExportError: LocalizedError {
        case processingServiceNotAvailable
        case exportFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .processingServiceNotAvailable:
                return "Сервис обработки изображений недоступен"
            case .exportFailed(let message):
                return "Ошибка экспорта: \(message)"
            }
        }
    }
    
    @MainActor
    private func exportPage(_ page: MangaPage, to url: URL) async throws {
        guard let imageProcessor = imageProcessor else {
            throw ExportError.processingServiceNotAvailable
        }
        
        // Если страница уже обработана, используем готовый результат
        if let processedImage = await page.processedImage?.image {
            try await exportService.saveImage(processedImage, to: url)
            return
        }
        
        // Если нет, обрабатываем страницу
        let regions = try await imageProcessor.recognizeText(in: page.originalImage)
        let translatedRegions = try await imageProcessor.translateRegions(regions, to: targetLanguage)
        let inpaintedImage = try await imageProcessor.inpaintTextRegions(
            wrapper: page.originalImage,
            regions: translatedRegions
        )
        let resultImage = try await imageProcessor.overlayTranslatedText(
            wrapper: inpaintedImage,
            regions: translatedRegions,
            targetLanguage: targetLanguage
        )
        
        try await exportService.saveImage(resultImage.image, to: url)
    }
} 
