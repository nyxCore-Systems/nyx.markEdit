//
//  AISettingsView.swift
//  MarkEditMac
//
//  Settings tab to configure the AI selection refactor feature.
//

import SwiftUI
import SettingsUI

@MainActor
struct AISettingsView: View {
  @State private var enabled = AppPreferences.AI.enabled
  @State private var apiKey: String = AppPreferences.AI.apiKey ?? ""
  @State private var model: String = AppPreferences.AI.model
  @State private var baseURL: String = AppPreferences.AI.baseURL
  @State private var maxTokens: Int = AppPreferences.AI.maxTokens
  @State private var testStatus: String = ""
  @State private var testStatusIsError: Bool = false
  @State private var isTesting: Bool = false

  var body: some View {
    SettingsForm {
      Section {
        Toggle(Localized.Settings.aiEnabled, isOn: $enabled)
          .onChange(of: enabled) {
            AppPreferences.AI.enabled = enabled
          }
          .formLabel(Localized.Settings.aiTitle)
      }

      Section {
        VStack(alignment: .leading) {
          SecureField("", text: $apiKey, prompt: Text("sk-ant-…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: apiKey) {
              AppPreferences.AI.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
            }

          Text(Localized.Settings.aiKeyHint)
            .formDescription()
        }
        .formLabel(alignment: .top, Localized.Settings.aiAPIKey)

        TextField("", text: $model)
          .textFieldStyle(.roundedBorder)
          .onChange(of: model) {
            AppPreferences.AI.model = model
          }
          .formLabel(Localized.Settings.aiModel)

        TextField("", text: $baseURL)
          .textFieldStyle(.roundedBorder)
          .onChange(of: baseURL) {
            AppPreferences.AI.baseURL = baseURL
          }
          .formLabel(Localized.Settings.aiBaseURL)

        Stepper(value: $maxTokens, in: 256...8192, step: 256) {
          Text("\(maxTokens)")
        }
        .onChange(of: maxTokens) {
          AppPreferences.AI.maxTokens = maxTokens
        }
        .formLabel(Localized.Settings.aiMaxTokens)
      }

      Section {
        HStack {
          Button(Localized.Settings.aiTestConnection) {
            runConnectionTest()
          }
          .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

          if isTesting {
            ProgressView().scaleEffect(0.6)
          }

          if !testStatus.isEmpty {
            Text(testStatus)
              .foregroundStyle(testStatusIsError ? .red : .green)
              .font(.callout)
          }

          Spacer()
        }
        .formLabel("")
      }
    }
  }

  private func runConnectionTest() {
    isTesting = true
    testStatus = ""
    testStatusIsError = false

    Task { @MainActor in
      let service = AppAIService()
      let response = await service.refactor(
        action: .improve,
        selection: "Test.",
        context: nil
      )
      isTesting = false
      if let error = response.error {
        testStatusIsError = true
        testStatus = error
      } else {
        testStatusIsError = false
        testStatus = Localized.Settings.aiTestSuccess
      }
    }
  }
}
