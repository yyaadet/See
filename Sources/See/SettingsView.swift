import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if settings.provider == .ollama {
                Section("Ollama Settings") {
                    LabeledContent("Base URL") {
                        TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                            .disableAutocorrection(true)
                    }

                    TextField("Model (e.g. llava, bakllava)", text: $settings.ollamaModel)
                        .disableAutocorrection(true)
                }
            } else {
                Section("OpenAI Settings") {
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $settings.openAIAPIKey)
                    }

                    TextField("Model (e.g. gpt-4o-mini, gpt-4o)", text: $settings.openAIModel)
                        .disableAutocorrection(true)
                }
            }
        }
        .navigationTitle("Settings")
        .frame(width: 460, height: 300)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
