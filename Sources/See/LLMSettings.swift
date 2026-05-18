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

    @Published var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }

    @Published var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: Keys.openAIAPIKey) }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    @Published var prompt: String

    @Published var ollamaModelList: [String] = []
    @Published var openAIModelList: [String] = []
    @Published var isFetchingModels = false

    init() {
        let defaults = UserDefaults.standard
        let providerValue = defaults.string(forKey: Keys.provider) ?? LLMProvider.ollama.rawValue

        self.provider = LLMProvider(rawValue: providerValue) ?? .ollama
        self.ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llava"
        self.openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? "https://api.openai.com/v1"
        self.openAIAPIKey = defaults.string(forKey: Keys.openAIAPIKey) ?? ""
        self.openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o-mini"
        self.prompt = defaults.string(forKey: Keys.prompt) ?? "Describe this image in detail. Include what objects are present, the scene, colors, composition, and any notable details. Be concise but thorough. Respond in the same language as the image filename if it's in Chinese, otherwise use English."
    }

    func fetchOllamaModels() async {
        guard let baseURL = URL(string: ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            isFetchingModels = false
            return
        }
        isFetchingModels = true
        do {
            let url = baseURL.appending(path: "api/tags")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                ollamaModelList = []
                isFetchingModels = false
                return
            }
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let dict = jsonObject as? [String: Any]
            let modelArray = dict?["models"] as? [[String: Any]] ?? []
            ollamaModelList = modelArray.compactMap { entry -> String? in
                entry["name"] as? String
            }

            let currentInList = ollamaModelList.contains { $0 == ollamaModel }
            if !currentInList {
                ollamaModel = ollamaModelList.first ?? ollamaModel
            }
        } catch {
            ollamaModelList = []
        }
        isFetchingModels = false
    }

    func fetchOpenAIModels() async {
        guard !openAIAPIKey.isEmpty else { return }
        guard var baseURL = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            openAIModelList = []
            isFetchingModels = false
            return
        }
        isFetchingModels = true
        do {
            if !baseURL.absoluteString.hasSuffix("/v1") && !baseURL.absoluteString.hasSuffix("/v1/") {
                baseURL = baseURL.appending(path: "/v1")
            }
            let url = baseURL.appending(path: "models")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                openAIModelList = []
                isFetchingModels = false
                return
            }
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let dict = jsonObject as? [String: Any]
            let modelArray = dict?["data"] as? [[String: Any]] ?? []
            var names = modelArray.compactMap { entry -> String? in
                entry["id"] as? String
            }

            names.sort { a, b in
                if a.hasPrefix("gpt-4") && !b.hasPrefix("gpt-4") { return true }
                if b.hasPrefix("gpt-4") && !a.hasPrefix("gpt-4") { return false }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }

            openAIModelList = names

            let currentInList = openAIModelList.contains { $0 == openAIModel }
            if !currentInList {
                openAIModel = openAIModelList.first ?? openAIModel
            }
        } catch {
            openAIModelList = []
        }
        isFetchingModels = false
    }

    private enum Keys {
        static let provider = "llm.provider"
        static let ollamaBaseURL = "llm.ollamaBaseURL"
        static let ollamaModel = "llm.ollamaModel"
        static let openAIBaseURL = "llm.openAIBaseURL"
        static let openAIAPIKey = "llm.openAIAPIKey"
        static let openAIModel = "llm.openAIModel"
        static let prompt = "llm.prompt"
    }
}
