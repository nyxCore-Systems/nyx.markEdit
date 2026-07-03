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
  /// The settings window has a fixed width (580); long single-line texts would
  /// otherwise inflate the form's ideal width and get clipped on both sides.
  private let descriptionWidth: Double = 340

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
  @State private var nyxPersonaToken: String = AppPreferences.NyxCore.personaToken ?? ""
  @State private var nyxPersonaBaseURL: String = AppPreferences.NyxCore.personaBaseURL
  @State private var nyxKnowledgeToken: String = AppPreferences.NyxCore.knowledgeToken ?? ""
  @State private var nyxKnowledgeBaseURL: String = AppPreferences.NyxCore.knowledgeBaseURL
  @State private var nyxProjectID: String = AppPreferences.NyxCore.projectID
  @State private var nyxCollectionID: String = AppPreferences.NyxCore.collectionID
  @State private var nyxKnowledgeScope: String = {
    let stored = AppPreferences.NyxCore.knowledgeScope
    if !stored.isEmpty {
      return stored
    }
    return AppPreferences.NyxCore.useKnowledge ? "project" : "off"
  }()
  @State private var knowledgeStatus: String = ""
  @State private var knowledgeStatusIsError: Bool = false
  @State private var knowledgeTesting: Bool = false
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
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button(Localized.Settings.aiTestConnection) {
              runConnectionTest()
            }
            .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

            if isTesting {
              ProgressView().scaleEffect(0.6)
            }
          }

          if !testStatus.isEmpty {
            Text(testStatus)
              .foregroundStyle(testStatusIsError ? .red : .green)
              .font(.callout)
              .frame(width: descriptionWidth, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .formLabel(alignment: .top, "")
      }

      // MARK: - nyxCore

      Section {
        Toggle("nyxCore personas & knowledge", isOn: $nyxEnabled)
          .onChange(of: nyxEnabled) {
            AppPreferences.NyxCore.enabled = nyxEnabled
          }
          .formLabel("nyxCore")
      }

      // Persona Studio credentials
      Section {
        VStack(alignment: .leading) {
          SecureField("", text: $nyxPersonaToken, prompt: Text("nyx_pa_… / nyx_mt_…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxPersonaToken) {
              AppPreferences.NyxCore.personaToken = nyxPersonaToken.trimmingCharacters(in: .whitespaces)
            }

          Text("Persona Studio token (nyx_pa_) or MCP token (nyx_mt_) — detected automatically. Stored in the Keychain.")
            .formDescription()
            .frame(width: descriptionWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .formLabel(alignment: .top, "Persona token")

        TextField("", text: $nyxPersonaBaseURL)
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxPersonaBaseURL) {
            AppPreferences.NyxCore.personaBaseURL = nyxPersonaBaseURL
          }
          .formLabel("Persona endpoint")
      }

      // Knowledge credentials (Axiom REST, with legacy MCP fallback)
      Section {
        VStack(alignment: .leading) {
          SecureField("", text: $nyxKnowledgeToken, prompt: Text("nyx_ax_…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxKnowledgeToken) {
              AppPreferences.NyxCore.knowledgeToken = nyxKnowledgeToken.trimmingCharacters(in: .whitespaces)
            }

          Text("Axiom token (nyx_ax_). A tenant-wide token enables the Global and All scopes; a project token is pinned to its project. Stored in the Keychain.")
            .formDescription()
            .frame(width: descriptionWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .formLabel(alignment: .top, "Knowledge token")

        TextField("", text: $nyxKnowledgeBaseURL)
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxKnowledgeBaseURL) {
            AppPreferences.NyxCore.knowledgeBaseURL = nyxKnowledgeBaseURL
          }
          .formLabel("Knowledge endpoint")

        VStack(alignment: .leading) {
          TextField("", text: $nyxProjectID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxProjectID) {
              AppPreferences.NyxCore.projectID = nyxProjectID.trimmingCharacters(in: .whitespaces)
            }

          Text("Project for the \"Project\" scope.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Project ID")

        VStack(alignment: .leading) {
          TextField("", text: $nyxCollectionID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxCollectionID) {
              AppPreferences.NyxCore.collectionID = nyxCollectionID.trimmingCharacters(in: .whitespaces)
            }

          Text("Standalone Axiom collection for the \"Global\" scope. Optional.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Collection ID")

        Picker("", selection: $nyxKnowledgeScope) {
          Text("Off").tag("off")
          Text("Project").tag("project")
          Text("Global").tag("global")
          Text("All").tag("all")
        }
        .pickerStyle(.segmented)
        .onChange(of: nyxKnowledgeScope) {
          AppPreferences.NyxCore.knowledgeScope = nyxKnowledgeScope
        }
        .formLabel("Default scope")
      }

      Section {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button("Test personas") {
              runNyxConnectionTest()
            }
            .disabled(nyxTesting || nyxPersonaToken.trimmingCharacters(in: .whitespaces).isEmpty)

            if nyxTesting {
              ProgressView().scaleEffect(0.6)
            }

            Button("Test knowledge") {
              runKnowledgeTest()
            }
            .disabled(knowledgeTesting || nyxKnowledgeToken.trimmingCharacters(in: .whitespaces).isEmpty)

            if knowledgeTesting {
              ProgressView().scaleEffect(0.6)
            }
          }

          if !nyxStatus.isEmpty {
            Text(nyxStatus)
              .foregroundStyle(nyxStatusIsError ? .red : .green)
              .font(.callout)
              .frame(width: descriptionWidth, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !knowledgeStatus.isEmpty {
            Text(knowledgeStatus)
              .foregroundStyle(knowledgeStatusIsError ? .red : .green)
              .font(.callout)
              .frame(width: descriptionWidth, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .formLabel(alignment: .top, "")
      }
    }
  }
}

// MARK: - Connection tests

private extension AISettingsView {
  func runKnowledgeTest() {
    knowledgeTesting = true
    knowledgeStatus = ""
    knowledgeStatusIsError = false

    Task { @MainActor in
      let result = await AppAIService().testKnowledge()
      knowledgeTesting = false
      knowledgeStatusIsError = !result.success
      knowledgeStatus = result.message
    }
  }

  func runNyxConnectionTest() {
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

  func runConnectionTest() {
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
