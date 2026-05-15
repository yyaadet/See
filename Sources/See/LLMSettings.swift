import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case ollama = "Ollama"
    case openAI = "OpenAI"

    var id: String { rawValue }
}

@MainActor
final class LLMSettings: ObservableObject {
    @Published var provider: LLMProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }

    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: Keys.openAIAPIKey) }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    init() {
        let defaults = UserDefaults.standard
        let providerValue = defaults.string(forKey: Keys.provider) ?? LLMProvider.ollama.rawValue

        self.provider = LLMProvider(rawValue: providerValue) ?? .ollama
        self.ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llava"
        self.openAIAPIKey = defaults.string(forKey: Keys.openAIAPIKey) ?? ""
        self.openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o-mini"
    }

    private enum Keys {
        static let provider = "llm.provider"
        static let ollamaBaseURL = "llm.ollamaBaseURL"
        static let ollamaModel = "llm.ollamaModel"
        static let openAIAPIKey = "llm.openAIAPIKey"
        static let openAIModel = "llm.openAIModel"
    }
}
