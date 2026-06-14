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

  // nyxCore
  @State private var nyxEnabled = AppPreferences.NyxCore.enabled
  @State private var nyxToken: String = AppPreferences.NyxCore.token ?? ""
  @State private var nyxBaseURL: String = AppPreferences.NyxCore.baseURL
  @State private var nyxProjectID: String = AppPreferences.NyxCore.projectID
  @State private var nyxUseKnowledge = AppPreferences.NyxCore.useKnowledge
  @State private var nyxStatus: String = ""
  @State private var nyxStatusIsError: Bool = false
  @State private var nyxTesting: Bool = false

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

      // MARK: - nyxCore

      Section {
        Toggle("nyxCore personas & knowledge", isOn: $nyxEnabled)
          .onChange(of: nyxEnabled) {
            AppPreferences.NyxCore.enabled = nyxEnabled
          }
          .formLabel("nyxCore")
      }

      Section {
        VStack(alignment: .leading) {
          SecureField("", text: $nyxToken, prompt: Text("nyx_mt_…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxToken) {
              AppPreferences.NyxCore.token = nyxToken.trimmingCharacters(in: .whitespaces)
            }

          Text("Bearer token for the nyxCore MCP endpoint. Stored in the Keychain.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Token")

        TextField("", text: $nyxBaseURL)
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxBaseURL) {
            AppPreferences.NyxCore.baseURL = nyxBaseURL
          }
          .formLabel("Endpoint")

        VStack(alignment: .leading) {
          TextField("", text: $nyxProjectID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxProjectID) {
              AppPreferences.NyxCore.projectID = nyxProjectID.trimmingCharacters(in: .whitespaces)
            }

          Text("Optional project to scope knowledge search.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Project ID")

        Toggle("Ground rewrites with project knowledge", isOn: $nyxUseKnowledge)
          .onChange(of: nyxUseKnowledge) {
            AppPreferences.NyxCore.useKnowledge = nyxUseKnowledge
          }
          .formLabel("Knowledge")
      }

      Section {
        HStack {
          Button("Test nyxCore") {
            runNyxConnectionTest()
          }
          .disabled(nyxTesting || nyxToken.trimmingCharacters(in: .whitespaces).isEmpty)

          if nyxTesting {
            ProgressView().scaleEffect(0.6)
          }

          if !nyxStatus.isEmpty {
            Text(nyxStatus)
              .foregroundStyle(nyxStatusIsError ? .red : .green)
              .font(.callout)
          }

          Spacer()
        }
        .formLabel("")
      }
    }
  }

  private func runNyxConnectionTest() {
    nyxTesting = true
    nyxStatus = ""
    nyxStatusIsError = false

    Task { @MainActor in
      let response = await AppAIService().listPersonas()
      nyxTesting = false
      if let error = response.error {
        nyxStatusIsError = true
        nyxStatus = error
      } else {
        nyxStatusIsError = false
        let count = response.personas?.count ?? 0
        nyxStatus = "Connected — \(count) personas"
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
