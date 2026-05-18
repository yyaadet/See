import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Provider selection
                Section("Provider") {
                    Picker("Type", selection: $settings.provider) {
                        Label("Ollama (Local)", systemImage: "cpu")
                            .tag(LLMProvider.ollama)
                        Label("OpenAI (Cloud)", systemImage: "cloud")
                            .tag(LLMProvider.openAI)
                    }
                    .pickerStyle(.segmented)
                }

                // Ollama section
                if settings.provider == .ollama {
                    Section("Ollama") {
                        LabeledContent("URL") {
                            TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                                .disableAutocorrection(true)
                        }

                        HStack(spacing: 8) {
                            if !settings.ollamaModelList.isEmpty {
                                Picker("Model", selection: $settings.ollamaModel) {
                                    ForEach(settings.ollamaModelList, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                TextField("Enter model name", text: $settings.ollamaModel)
                                    .disableAutocorrection(true)
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                Task { await settings.fetchOllamaModels() }
                            } label: {
                                Image(systemName: settings.isFetchingModels ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .disabled(settings.isFetchingModels)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                        }
                    }
                } else {
                    Section("OpenAI") {
                        LabeledContent("Base URL") {
                            TextField("https://api.openai.com/v1", text: $settings.openAIBaseURL)
                                .disableAutocorrection(true)
                        }

                        LabeledContent("API Key") {
                            SecureField("sk-...", text: $settings.openAIAPIKey)
                        }

                        HStack(spacing: 8) {
                            if !settings.openAIModelList.isEmpty {
                                Picker("Model", selection: $settings.openAIModel) {
                                    ForEach(settings.openAIModelList, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                TextField("Enter model name", text: $settings.openAIModel)
                                    .disableAutocorrection(true)
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                Task { await settings.fetchOpenAIModels() }
                            } label: {
                                Image(systemName: settings.isFetchingModels ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .disabled(settings.isFetchingModels)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                        }
                    }
                }

                // Prompt section
                Section("Prompt") {
                    TextEditor(text: $settings.prompt)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(3)
                        .frame(height: 140)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        UserDefaults.standard.set(settings.prompt, forKey: "llm.prompt")
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .frame(width: 480, height: 400)
        }
    }
}
