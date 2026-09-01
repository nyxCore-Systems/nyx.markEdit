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
  @State private var nyxSources: [KnowledgeSourcePreference] = KnowledgeSourcePreference.load()
  @State private var nyxProjects: [NyxProject] = []
  @State private var projectsLoading: Bool = false
  @State private var projectListStatus: String = ""
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
              AppPreferences.AI.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
            .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
              AppPreferences.NyxCore.personaToken = nyxPersonaToken.trimmingCharacters(in: .whitespacesAndNewlines)
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

      knowledgeSection

      Section {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button("Test personas") {
              runNyxConnectionTest()
            }
            .disabled(nyxTesting || nyxPersonaToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if nyxTesting {
              ProgressView().scaleEffect(0.6)
            }

            Button("Test knowledge") {
              runKnowledgeTest()
            }
            .disabled(knowledgeTesting || nyxKnowledgeToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

// MARK: - nyxCore knowledge

private extension AISettingsView {
  /// Lives in an extension so the form body stays inside SwiftLint's
  /// type_body_length budget as the nyxCore settings keep growing.
  @ViewBuilder var knowledgeSection: some View {
    Section {
      VStack(alignment: .leading) {
        SecureField("", text: $nyxKnowledgeToken, prompt: Text("nyx_ax_…"))
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxKnowledgeToken) {
            AppPreferences.NyxCore.knowledgeToken = nyxKnowledgeToken.trimmingCharacters(in: .whitespacesAndNewlines)
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
        HStack(spacing: 6) {
          TextField("", text: $nyxProjectID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxProjectID) {
              AppPreferences.NyxCore.projectID = nyxProjectID.trimmingCharacters(in: .whitespaces)
            }

          projectChooser { project in
            nyxProjectID = project.id
          }
        }

        Text("Project for the \"Project\" scope.")
          .formDescription()

        if !projectListStatus.isEmpty {
          Text(projectListStatus)
            .formDescription()
            .foregroundStyle(.secondary)
            .frame(width: descriptionWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .formLabel(alignment: .top, "Project ID")

      VStack(alignment: .leading) {
        TextField("", text: $nyxCollectionID, prompt: Text("UUID"))
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxCollectionID) {
            AppPreferences.NyxCore.collectionID = nyxCollectionID.trimmingCharacters(in: .whitespaces)
          }

        Text("Standalone Axiom collection for the \"Global\" scope. Optional. "
          + "Collections cannot be listed by the API, so this one is typed in.")
          .formDescription()
          .frame(width: descriptionWidth, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .formLabel(alignment: .top, "Collection ID")

      VStack(alignment: .leading, spacing: 8) {
        ForEach(nyxSources.indices, id: \.self) { index in
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              TextField("", text: $nyxSources[index].name, prompt: Text("Display name"))
                .textFieldStyle(.roundedBorder)

              Button {
                nyxSources.remove(at: index)
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.borderless)
              .help("Remove this source")
            }

            HStack(spacing: 6) {
              Picker("", selection: $nyxSources[index].kind) {
                Text("Axiom project").tag("project")
                Text("Axiom collection").tag("collection")
                Text("Project + patterns").tag("nyxproject")
              }
              .labelsHidden()
              .frame(width: 150)

              TextField("", text: $nyxSources[index].target, prompt: Text("UUID"))
                .textFieldStyle(.roundedBorder)

              if nyxSources[index].kind != "collection" {
                // Picking a project fills the display name too — an unnamed
                // row is ignored on load, and typing the name again is the
                // step people skip.
                projectChooser { project in
                  nyxSources[index].target = project.id
                  if nyxSources[index].name.trimmingCharacters(in: .whitespaces).isEmpty {
                    nyxSources[index].name = project.name
                  }
                }
              }
            }
          }
        }

        Button("Add source") {
          nyxSources.append(KnowledgeSourcePreference(kind: "project", target: "", name: ""))
        }

        Text("Offered in the editor's source picker. \"Project + patterns\" also pulls "
          + "the project's patterns, solutions and pains; the Axiom kinds search "
          + "documents only. Incomplete rows are ignored.")
          .formDescription()
          .frame(width: descriptionWidth, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: descriptionWidth, alignment: .leading)
      .onChange(of: nyxSources) {
        KnowledgeSourcePreference.save(nyxSources)
      }
      .formLabel(alignment: .top, "Knowledge sources")

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

// MARK: - Project chooser

private extension AISettingsView {
  /// Menu that fills a project UUID by name.
  ///
  /// The field stays a text field rather than becoming a pure picker: a token
  /// that cannot list projects, or a project the catalog does not return, must
  /// still be usable by pasting the id. The menu is a convenience over that,
  /// not a replacement for it.
  ///
  /// Collections have no listing endpoint on either the Axiom REST API or the
  /// MCP catalog, so they get no equivalent — the Collection ID description
  /// says so instead of leaving an empty menu to explain itself.
  @ViewBuilder
  func projectChooser(onPick: @escaping (NyxProject) -> Void) -> some View {
    Menu {
      if nyxProjects.isEmpty {
        Text(projectsLoading ? "Loading…" : "No projects loaded")
      } else {
        ForEach(nyxProjects) { project in
          Button(project.name) { onPick(project) }
        }
      }

      Divider()
      Button(nyxProjects.isEmpty ? "Load projects" : "Reload projects") {
        loadProjects()
      }
    } label: {
      Text("Choose")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .disabled(projectsLoading)
    .help("Pick a project by name instead of pasting its UUID")
  }

  func loadProjects() {
    projectsLoading = true
    projectListStatus = ""

    Task { @MainActor in
      defer { projectsLoading = false }

      guard let client = NyxCoreClient.directory() else {
        projectListStatus = "Listing projects needs an MCP persona token (nyx_mt_). "
          + "With a Persona Studio token, enter the ID manually."
        return
      }

      do {
        nyxProjects = try await client.listProjects()
        projectListStatus = nyxProjects.isEmpty
          ? "No active projects returned for this token."
          : "\(nyxProjects.count) projects loaded."
      } catch {
        nyxProjects = []
        projectListStatus = error.localizedDescription
      }
    }
  }
}
