//
//  AppAIService.swift
//  MarkEditMac
//
//  Anthropic-backed implementation of the AIService bridge protocol.
//

import Foundation
import MarkEditKit

@MainActor
final class AppAIService: AIService {
  private static let userAgent = "MarkEdit"
  private static let anthropicVersion = "2023-06-01"

  func isConfigured() async -> Bool {
    guard AppPreferences.AI.enabled else {
      return false
    }
    let key = AppPreferences.AI.apiKey ?? ""
    return !key.trimmingCharacters(in: .whitespaces).isEmpty
  }

  func refactor(action: AIAction, selection: String, context: String?) async -> AIRefactorResponse {
    let prompt = buildPrompt(action: action, selection: selection, context: context)
    return await complete(system: Self.systemPrompt, userMessage: prompt)
  }

  func listPersonas() async -> AIPersonaListResponse {
    switch Self.resolvePersonaRoute() {
    case let .unavailable(message):
      return .init(error: message)

    case let .studio(studio):
      do {
        let personas = try await studio.listPersonas()
        guard !personas.isEmpty else {
          return .init(error: "No published circles for this token.")
        }

        return .init(personas: personas.map {
          AIPersona(
            id: $0.id,
            name: $0.name,
            description: $0.description,
            source: "studio",
            circleId: $0.circleID,
            circleName: $0.circleName
          )
        })
      } catch {
        return .init(error: error.localizedDescription)
      }

    case .mcp:
      guard let client = NyxCoreClient.personas() else {
        return .init(error: Self.personaDisabledMessage)
      }

      do {
        let personas = try await client.listPersonas()
        return .init(personas: personas.map {
          AIPersona(id: $0.id, name: $0.name, description: $0.description, source: "mcp")
        })
      } catch {
        return .init(error: error.localizedDescription)
      }
    }
  }

  func knowledgeConfig() async -> AIKnowledgeConfig {
    var scopes = ["off"]

    switch Self.resolveKnowledgeRoute() {
    case let .axiom(axiom):
      if axiom.projectID != nil {
        scopes.append("project")
      }
      if axiom.collectionID != nil {
        scopes.append("global")
      }
      scopes.append("all")

    case .legacy:
      // Legacy MCP knowledge token: only project-scoped search is possible.
      scopes.append("project")

    case .disabled, .invalidAxiomURL, .unavailable:
      break // Off-only: same source of truth loadKnowledge/testKnowledge gate on.
    }

    let preferred = Self.resolvedDefaultScope()
    let defaultScope = scopes.contains(preferred) ? preferred : (scopes.count > 1 ? scopes[1] : "off")
    return AIKnowledgeConfig(availableScopes: scopes, defaultScope: defaultScope)
  }

  // swiftlint:disable:next function_parameter_count
  func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> AIRefactorResponse {
    // Knowledge is best-effort for both protocols: failures never block the rewrite.
    let knowledge = await loadKnowledge(scope: knowledgeScope, query: selection)
    let user = NyxCorePromptComposer.userPrompt(selection: selection, context: context, knowledge: knowledge)

    switch Self.resolvePersonaRoute() {
    case let .unavailable(message):
      return .init(error: message)

    case let .studio(studio):
      do {
        let content = try await studio.chat(
          personaID: personaID,
          circleID: circleID,
          system: NyxCorePromptComposer.editorContract,
          user: user,
          maxTokens: AppPreferences.AI.maxTokens
        )
        return .init(result: content)
      } catch {
        return .init(error: error.localizedDescription)
      }

    case .mcp:
      // MCP: fetch the persona's skill prompts, then generate locally via Anthropic.
      guard let personaClient = NyxCoreClient.personas() else {
        return .init(error: Self.personaDisabledMessage)
      }

      do {
        let personaPrompt = try await personaClient.personaPrompt(personaID: personaID)
        let system = NyxCorePromptComposer.systemPrompt(personaName: personaName, personaPrompt: personaPrompt)
        return await complete(system: system, userMessage: user)
      } catch {
        return .init(error: error.localizedDescription)
      }
    }
  }

  /// Test hook for Settings → AI: runs a 1-result search in the default scope
  /// and surfaces errors instead of swallowing them.
  func testKnowledge() async -> (success: Bool, message: String) {
    let scope = Self.resolvedDefaultScope()
    guard scope != "off" else {
      return (false, "Knowledge is off — pick a default scope first.")
    }

    do {
      let snippets: [String]
      switch Self.resolveKnowledgeRoute() {
      case .disabled:
        return (false, "Enable nyxCore and add a knowledge token (nyx_ax_) in Settings → AI.")
      case .invalidAxiomURL:
        return (false, "Invalid Axiom endpoint URL — check Settings → AI.")
      case let .axiom(axiom):
        snippets = try await axiom.search(query: "test", scope: scope, limit: 1)
      case let .legacy(legacy):
        guard scope == "project" else {
          return (false, "Add a knowledge token (nyx_ax_) in Settings → AI.")
        }
        snippets = try await legacy.search(query: "test", limit: 1)
      case .unavailable:
        return (false, "Add a knowledge token (nyx_ax_) in Settings → AI.")
      }
      return (true, "Connected — \(snippets.count) result(s)")
    } catch {
      return (false, error.localizedDescription)
    }
  }

  // MARK: - Generation (Anthropic)

  /// Shared text-generation call. nyxCore supplies the persona/knowledge context;
  /// this method is the generation provider seam (currently Anthropic only).
  private func complete(system: String, userMessage: String) async -> AIRefactorResponse {
    guard AppPreferences.AI.enabled else {
      return .init(error: "AI is disabled in Settings.")
    }
    guard let apiKey = AppPreferences.AI.apiKey?.trimmingCharacters(in: .whitespaces), !apiKey.isEmpty else {
      return .init(error: "Add your Anthropic API key in Settings → AI.")
    }

    let baseURL = AppPreferences.AI.baseURL
    guard let url = URL(string: "\(baseURL.trimmingTrailingSlash())/messages") else {
      return .init(error: "Invalid AI endpoint URL.")
    }

    let body: [String: Any] = [
      "model": AppPreferences.AI.model,
      "max_tokens": AppPreferences.AI.maxTokens,
      "system": system,
      "messages": [
        [
          "role": "user",
          "content": userMessage,
        ],
      ],
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .init(error: "Invalid response from AI endpoint.")
      }

      guard (200...299).contains(httpResponse.statusCode) else {
        let detail = Self.extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
        return .init(error: "AI request failed: \(detail)")
      }

      guard let text = Self.extractText(from: data) else {
        return .init(error: "Could not parse AI response.")
      }

      return .init(result: text)
    } catch {
      return .init(error: error.localizedDescription)
    }
  }

  // MARK: - Prompts

  private static let systemPrompt = """
  You are a precise text editor for Markdown documents. The user will provide a passage and ask \
  you to rewrite it. Output only the rewritten passage — no preamble, no explanation, no quoting, \
  no surrounding code fences. Preserve the original Markdown formatting style: keep inline code, \
  links, bold/italic markers, list markers, and heading levels intact. Match the language of the \
  selection. If there is nothing meaningful to change, return the original text verbatim.
  """

  private func buildPrompt(action: AIAction, selection: String, context: String?) -> String {
    let instruction: String = {
      switch action {
      case .improve:
        return "Improve clarity, flow, and word choice without changing the meaning or length materially."
      case .shorten:
        return "Make this significantly shorter while preserving the key meaning. Aim for ~50% length."
      case .expand:
        return "Expand this with more detail, examples, or supporting points. Stay on topic."
      case .fixGrammar:
        return "Fix grammar, spelling, and punctuation. Make minimal stylistic changes."
      case .toneProfessional:
        return "Rewrite in a professional, neutral tone."
      case .toneCasual:
        return "Rewrite in a casual, conversational tone."
      case .toneFriendly:
        return "Rewrite in a warm, friendly tone."
      case .toneAcademic:
        return "Rewrite in a formal academic tone with precise vocabulary."
      }
    }()

    var parts: [String] = []
    parts.append("Instruction: \(instruction)")

    if let context, !context.isEmpty, context != selection {
      parts.append("Surrounding context (for style only — do not rewrite this):\n\(context)")
    }

    parts.append("Passage to rewrite:\n\(selection)")
    return parts.joined(separator: "\n\n")
  }

  // MARK: - Response parsing

  private static func extractText(from data: Data) -> String? {
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let content = json["content"] as? [[String: Any]]
    else {
      return nil
    }

    let parts: [String] = content.compactMap { block in
      guard let type = block["type"] as? String, type == "text" else { return nil }
      return block["text"] as? String
    }

    let joined = parts.joined()
    return joined.isEmpty ? nil : joined
  }

  private static func extractErrorMessage(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
      return message
    }
    return nil
  }
}

// MARK: - Protocol routing

private extension AppAIService {
  /// Which persona protocol the current settings resolve to. Routing commits
  /// on token PREFIX: a matching prefix never falls through to the other
  /// protocol, even when the resolved client can't be constructed (e.g. a
  /// bad endpoint URL) — that would otherwise send the wrong token as Bearer
  /// to the wrong endpoint.
  enum PersonaRoute {
    case studio(PersonaStudioClient)
    case mcp
    case unavailable(String)
  }

  static let personaDisabledMessage =
    "Enable nyxCore and add a persona token (nyx_pa_ or nyx_mt_) in Settings → AI."

  @MainActor
  static func resolvePersonaRoute() -> PersonaRoute {
    guard AppPreferences.NyxCore.enabled else {
      return .unavailable(personaDisabledMessage)
    }

    let token = (AppPreferences.NyxCore.personaToken ?? "").trimmingCharacters(in: .whitespaces)
    guard token.hasPrefix(PersonaStudioClient.tokenPrefix) else {
      return .mcp
    }

    guard let studio = PersonaStudioClient.current() else {
      return .unavailable("Invalid Persona Studio endpoint URL — check Settings → AI.")
    }

    return .studio(studio)
  }

  /// Which knowledge protocol the current settings resolve to. Mirrors
  /// `PersonaRoute`: a matching nyx_ax_ prefix commits to Axiom and never
  /// falls through to the legacy MCP branch. Shared by knowledgeConfig,
  /// testKnowledge, and loadKnowledge so all three gate identically.
  enum KnowledgeRoute {
    case axiom(AxiomClient)
    case legacy(NyxCoreClient)
    case disabled
    case invalidAxiomURL
    case unavailable
  }

  @MainActor
  static func resolveKnowledgeRoute() -> KnowledgeRoute {
    guard AppPreferences.NyxCore.enabled else {
      return .disabled
    }

    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespaces)
    if token.hasPrefix(AxiomClient.tokenPrefix) {
      guard let axiom = AxiomClient.current() else {
        return .invalidAxiomURL
      }
      return .axiom(axiom)
    }

    guard let legacy = NyxCoreClient.knowledge() else {
      return .unavailable
    }
    return .legacy(legacy)
  }

  /// The effective default scope, migrating from the legacy useKnowledge flag
  /// when the new preference has never been set.
  static func resolvedDefaultScope() -> String {
    let stored = AppPreferences.NyxCore.knowledgeScope
    if !stored.isEmpty {
      return stored
    }
    return AppPreferences.NyxCore.useKnowledge ? "project" : "off"
  }

  func loadKnowledge(scope: String, query: String) async -> [String] {
    guard scope != "off" else {
      return []
    }

    let limit = max(1, AppPreferences.NyxCore.knowledgeLimit)

    switch Self.resolveKnowledgeRoute() {
    case let .axiom(axiom):
      // Best-effort: an unconstructible client already stops us before this
      // point, so only the search call itself can still fail — never block
      // a rewrite on a knowledge failure.
      return (try? await axiom.search(query: query, scope: scope, limit: limit)) ?? []
    case let .legacy(legacy) where scope == "project":
      return (try? await legacy.search(query: query, limit: limit)) ?? []
    default:
      return []
    }
  }
}

// MARK: - Helpers

private extension String {
  func trimmingTrailingSlash() -> String {
    hasSuffix("/") ? String(dropLast()) : self
  }
}
