import Foundation
import SwiftUI

@MainActor
final class ImageDescriber {
    private let settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    enum DescribeError: Swift.Error, LocalizedError {
        case invalidResponse
        case networkError(Swift.Error)
        case unauthorized
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from the LLM provider."
            case .networkError(let err):
                return "Network error: \(err.localizedDescription)"
            case .unauthorized:
                return "Authentication failed. Check your API key."
            case .unknown(let msg):
                return msg
            }
        }
    }

    typealias Error = DescribeError

    func describe(imageURL: URL, prompt: String? = nil) async throws -> String {
        let imageData = try Data(contentsOf: imageURL)
        let base64 = imageData.base64EncodedString()
        let mimeType = mimeType(for: imageURL)

        let defaultPrompt = """
        Describe this image in detail. Include what objects are present, the scene, colors, composition, and any notable details.
        Be concise but thorough. Respond in the same language as the image filename if it's in Chinese, otherwise use English.
        """

        let systemPrompt = prompt ?? defaultPrompt

        switch settings.provider {
        case .ollama:
            return try await describeWithOllama(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt
            )
        case .openAI:
            return try await describeWithOpenAI(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt
            )
        }
    }

    private func describeWithOllama(
        base64: String,
        mimeType: String,
        systemPrompt: String
    ) async throws -> String {
        let url = URL(string: settings.ollamaBaseURL)!.appending(path: "api/chat")

        let body: [String: Any] = [
            "model": settings.ollamaModel,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ] as [String: Any],
                [
                    "role": "user",
                    "content": "",
                    "images": [base64]
                ] as [String: Any]
            ],
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw Error.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw Error.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let message = json?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw Error.invalidResponse
        }

        return content
    }

    private func describeWithOpenAI(
        base64: String,
        mimeType: String,
        systemPrompt: String
    ) async throws -> String {
        guard !settings.openAIAPIKey.isEmpty else {
            throw Error.unauthorized
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        let body: [String: Any] = [
            "model": settings.openAIModel,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ] as [String: Any],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Please describe this image in detail."
                        ] as [String: Any],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:\(mimeType);base64,\(base64)",
                                "detail": "high"
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ] as [String: Any]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.networkError(NSError(domain: "No response", code: -1))
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw Error.unauthorized
        }

        if httpResponse.statusCode != 200 {
            let errorDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = errorDict?["error"] as? [String: Any]
            let msg = errMsg?["message"] as? String ?? "Request failed with status \(httpResponse.statusCode)"
            throw Error.unknown(msg)
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = result?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String

        guard let content, !content.isEmpty else {
            throw Error.invalidResponse
        }

        return content
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        default: return "image/jpeg"
        }
    }
}
