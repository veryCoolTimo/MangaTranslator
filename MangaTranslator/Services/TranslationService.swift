import Foundation

actor TranslationService {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    
    init() throws {
        // Пробуем получить API ключ из разных источников
        if let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            print("API ключ найден в переменных окружения")
            self.apiKey = envApiKey
        } else if let fileApiKey = try? Self.readAPIKeyFromEnvFile() {
            print("API ключ найден в .env файле")
            self.apiKey = fileApiKey
        } else {
            print("API ключ не найден")
            throw TranslationError.missingAPIKey
        }
    }
    
    private static func readAPIKeyFromEnvFile() throws -> String? {
        print("Ищу файл .env в ресурсах приложения")
        
        // Получаем путь к файлу .env в ресурсах приложения
        guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("❌ Файл .env не найден в ресурсах приложения")
            return nil
        }
        
        print("✅ Найден .env файл в: \(envPath)")
        
        do {
            let content = try String(contentsOfFile: envPath, encoding: .utf8)
            print("📄 Содержимое файла:")
            print(content)
            
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                    let key = parts[1].trimmingCharacters(in: .whitespaces)
                    print("🔑 Найден ключ API в файле")
                    return key
                }
            }
            print("❌ Ключ API не найден в содержимом файла")
        } catch {
            print("❌ Ошибка при чтении файла: \(error)")
        }
        
        return nil
    }
    
    func translate(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> Translation {
        let prompt = """
        Переведи следующий текст манхвы с корейского на \(targetLanguage).
        Сохрани стиль и тон оригинала, учитывая особенности корейской манхвы.
        Текст должен звучать естественно и подходить для разговорной речи.
        Сохрани все восклицания и звукоподражания в соответствующем стиле.
        
        Текст: \(text)
        
        не пиши "перевод"
        """
        
        let messages: [[String: String]] = [
            ["role": "system", "content": """
            Ты - профессиональный переводчик корейской манхвы.
            Твоя задача - создавать естественно звучащие переводы, сохраняя:
            - Разговорный стиль и эмоциональный окрас
            - Корейские особенности речи и выражений
            - Правильную передачу звукоподражаний и восклицаний
            - Культурный контекст, где это важно
            """],
            ["role": "user", "content": prompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // не меняй этот параметр 
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 150
        ]
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let translatedText = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }
        
        return Translation(
            originalText: text,
            translatedText: translatedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            confidence: 0.9
        )
    }
    
    func translateBatch(_ texts: [String], from sourceLanguage: String, to targetLanguage: String) async throws -> [Translation] {
        // Переводим тексты параллельно
        return try await withThrowingTaskGroup(of: Translation.self) { group in
            for text in texts {
                group.addTask {
                    try await self.translate(text, from: sourceLanguage, to: targetLanguage)
                }
            }
            
            var translations: [Translation] = []
            for try await translation in group {
                translations.append(translation)
            }
            return translations
        }
    }
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Отсутствует API ключ OpenAI. Пожалуйста, добавьте ключ в файл .env или установите переменную окружения OPENAI_API_KEY"
        case .invalidResponse:
            return "Некорректный ответ от API"
        case .apiError(let message):
            return "Ошибка API: \(message)"
        }
    }
} 