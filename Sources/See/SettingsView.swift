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

                    HStack {
                        if !settings.ollamaModelList.isEmpty {
                            Picker("Model", selection: $settings.ollamaModel) {
                                ForEach(settings.ollamaModelList, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            TextField("Model name", text: $settings.ollamaModel)
                                .disableAutocorrection(true)
                                .italic()
                                .foregroundColor(.secondary)
                        }

                        Button {
                            Task {
                                await settings.fetchOllamaModels()
                            }
                        } label: {
                            Image(systemName: settings.isFetchingModels ? "arrow.2.circle" : "arrow.clockwise.circle")
                        }
                        .disabled(settings.isFetchingModels)
                    }
                }
            } else {
                Section("OpenAI Settings") {
                    LabeledContent("Base URL") {
                        TextField("https://api.openai.com/v1", text: $settings.openAIBaseURL)
                            .disableAutocorrection(true)
                    }

                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $settings.openAIAPIKey)
                    }

                    HStack {
                        if !settings.openAIModelList.isEmpty {
                            Picker("Model", selection: $settings.openAIModel) {
                                ForEach(settings.openAIModelList, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            TextField("Model name", text: $settings.openAIModel)
                                .disableAutocorrection(true)
                                .italic()
                                .foregroundColor(.secondary)
                        }

                        Button {
                            Task {
                                await settings.fetchOpenAIModels()
                            }
                        } label: {
                            Image(systemName: settings.isFetchingModels ? "arrow.2.circle" : "arrow.clockwise.circle")
                        }
                        .disabled(settings.isFetchingModels)
                    }
                }
            }

            Section("Prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom prompt for image description. Leave empty to use the default prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $settings.prompt)
                        .font(.caption)
                        .frame(height: 100)
                }
            }
        }
        .navigationTitle("Settings")
        .frame(width: 460, height: 320)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .task(id: settings.provider) {
            if settings.provider == .ollama {
                await settings.fetchOllamaModels()
            } else {
                await settings.fetchOpenAIModels()
            }
        }
    }
}
