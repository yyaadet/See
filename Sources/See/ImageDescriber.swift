import Foundation
import SwiftUI

@MainActor
final class ImageDescriber {
    private let settings: LLMSettings
    private let cache: ImageCache?

    init(settings: LLMSettings, cache: ImageCache? = nil) {
        self.settings = settings
        self.cache = cache
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
        // Check cache first
        if let cached = cache?.description(for: imageURL.path) {
            return cached
        }

        // Load image and convert to PNG to ensure compatibility with all APIs
        guard let nsImage = NSImage(contentsOf: imageURL) else {
            throw Error.unknown("Failed to load image from \(imageURL.path)")
        }

        guard let bitmap = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Error.unknown("Failed to convert image to bitmap")
        }

        let representation = NSBitmapImageRep(cgImage: bitmap)
        let imageData = representation.representation(using: .png, properties: [:]) ?? nsImage.tiffRepresentation!

        let base64 = imageData.base64EncodedString()
        let mimeType = "image/png"

        let systemPrompt = "You are speaking as an AI assistant. Describe the image to me."

        let userPrompt = prompt ?? settings.prompt

        let result: String
        switch settings.provider {
        case .ollama:
            result = try await describeWithOllama(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        case .openAI:
            result = try await describeWithOpenAI(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        }

        // Save to cache
        cache?.saveDescription(result, for: imageURL.path)

        return result
    }

    private func describeWithOllama(
        base64: String,
        mimeType: String,
        systemPrompt: String,
        userPrompt: String
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
                    "content": userPrompt,
                    "images": [base64]
                ] as [String: Any]
            ],
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw Error.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            let errMsg = parseErrorMessage(from: data)
            throw Error.unknown(errMsg ?? "Request failed with status \(httpResponse.statusCode)")
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
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        guard !settings.openAIAPIKey.isEmpty else {
            throw Error.unauthorized
        }

        guard var baseURL = URL(string: settings.openAIBaseURL.trimmingCharacters(in: .whitespaces)) else {
            throw Error.unknown("Invalid base URL. Check your settings.")
        }
        if !baseURL.absoluteString.hasSuffix("/v1") && !baseURL.absoluteString.hasSuffix("/v1/") {
            baseURL = baseURL.appending(path: "/v1")
        }
        let url = baseURL.appending(path: "chat/completions")

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
                            "text": userPrompt
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
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.networkError(NSError(domain: "No response", code: -1))
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw Error.unauthorized
        }

        if httpResponse.statusCode != 200 {
            let errMsg = parseErrorMessage(from: data)
            throw Error.unknown(errMsg ?? "Request failed with status \(httpResponse.statusCode)")
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

    private func parseErrorMessage(from data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            return error["message"] as? String ?? error["type"] as? String
        }
        if let message = json?["message"] as? String {
            return message
        }
        if let detail = json?["detail"] as? String {
            return detail
        }
        if let error = json?["error"] as? String {
            return error
        }
        return nil
    }

    func explain(imageURL: URL, prompt: String? = nil) async throws -> String {
        let cachedDescription = cache?.description(for: imageURL.path)
        let cachedExplanation = cache?.explanation(for: imageURL.path)

        if let cachedExplanation {
            return cachedExplanation
        }

        guard let description = cachedDescription else {
            let descriptionText = try await describe(imageURL: imageURL)
            return try await describeExplanation(
                imageURL: imageURL,
                description: descriptionText,
                prompt: prompt
            )
        }

        return try await describeExplanation(
            imageURL: imageURL,
            description: description,
            prompt: prompt
        )
    }

    private func describeExplanation(
        imageURL: URL,
        description: String,
        prompt: String?
    ) async throws -> String {
        guard let nsImage = NSImage(contentsOf: imageURL) else {
            throw Error.unknown("Failed to load image from \(imageURL.path)")
        }

        guard let bitmap = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Error.unknown("Failed to convert image to bitmap")
        }

        let representation = NSBitmapImageRep(cgImage: bitmap)
        let imageData = representation.representation(using: .png, properties: [:]) ?? nsImage.tiffRepresentation!

        let base64 = imageData.base64EncodedString()
        let mimeType = "image/png"

        let systemPrompt = "You are speaking as an AI assistant. Explain the image to me."

        let userPrompt = prompt ?? """
        I already have a description of this image:
        \(description)

        Please explain this image in more detail. What is the context, mood, and story behind it?
        Respond in the same language as the original description.
        """

        let result: String
        switch settings.provider {
        case .ollama:
            result = try await describeWithOllama(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        case .openAI:
            result = try await describeWithOpenAI(
                base64: base64,
                mimeType: mimeType,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        }

        cache?.saveExplanation(result, for: imageURL.path)

        return result
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
