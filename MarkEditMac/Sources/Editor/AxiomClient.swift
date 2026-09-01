//
//  AxiomClient.swift
//  MarkEditMac
//
//  REST client for the nyxCore Axiom RAG search API (nyx_ax_ tokens).
//  Scope mapping: "project" → projectId, "global" → collectionId (standalone
//  collection), "all" → neither (tenant-wide; requires a tenant-wide token —
//  project-scoped tokens are pinned server-side and degrade to their project).
//

import Foundation

/// A named knowledge source the user configured in Settings → AI, on top of the
/// single Project ID / Collection ID pair that the legacy scopes use.
///
/// Persisted as a JSON array under `nyxcore.knowledge-sources` so the list can
/// grow without a new preference key per entry.
struct KnowledgeSourcePreference: Codable, Equatable, Sendable, Identifiable {
  /// "project" (Axiom project), "collection" (Axiom collection), or
  /// "nyxproject" (a whole nyxCore project: Axiom passages plus its patterns
  /// and insights, via MCP).
  var kind: String
  /// The project or collection UUID this source points at.
  var target: String
  var name: String

  /// Routing key handed to the web side and back: the target travels with the
  /// id, so resolving a pick never needs a second lookup into preferences.
  var id: String { kind == "nyxproject" ? "nyx:\(target)" : "\(kind):\(target)" }

  var isValid: Bool {
    ["project", "collection", "nyxproject"].contains(kind)
      && !target.trimmingCharacters(in: .whitespaces).isEmpty
      && !name.trimmingCharacters(in: .whitespaces).isEmpty
  }

  @MainActor
  static func load() -> [Self] {
    let raw = AppPreferences.NyxCore.knowledgeSources
    guard let data = raw.data(using: .utf8), !raw.isEmpty else {
      return []
    }

    return ((try? JSONDecoder().decode([Self].self, from: data)) ?? []).filter { $0.isValid }
  }

  @MainActor
  static func save(_ sources: [Self]) {
    guard let data = try? JSONEncoder().encode(sources), let json = String(data: data, encoding: .utf8) else {
      return
    }

    AppPreferences.NyxCore.knowledgeSources = json
  }
}

struct AxiomClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case missingProject
    case missingCollection
    case invalidScope(String)
    case notTenantWide
    case decoding(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid Axiom endpoint URL."
      case let .http(code, detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Axiom request failed: HTTP \(code)" : "Axiom request failed: \(trimmed)"
      case .missingProject:
        return "Set a Project ID in Settings → AI to use project-scoped knowledge."
      case .missingCollection:
        return "Set a Collection ID in Settings → AI to use global knowledge."
      case let .invalidScope(scope):
        return "Unknown knowledge scope: \(scope)."
      case .notTenantWide:
        return "This token covers several projects, so \"All\" is ambiguous — "
          + "pick a Project or Collection instead, or use a tenant-wide token."
      case let .decoding(message):
        return "Could not parse Axiom response: \(message)"
      }
    }
  }

  static let tokenPrefix = "nyx_ax_"

  let origin: String
  let token: String
  let projectID: String?
  let collectionID: String?

  /// Client for Axiom knowledge search, or nil when nyxCore is disabled or the
  /// knowledge token is not an Axiom (nyx_ax_) token.
  @MainActor
  static func current() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.hasPrefix(tokenPrefix) else {
      return nil
    }

    guard let origin = PersonaStudioClient.origin(from: AppPreferences.NyxCore.knowledgeBaseURL) else {
      return nil
    }

    let project = AppPreferences.NyxCore.projectID.trimmingCharacters(in: .whitespaces)
    let collection = AppPreferences.NyxCore.collectionID.trimmingCharacters(in: .whitespaces)
    return Self(
      origin: origin,
      token: token,
      projectID: project.isEmpty ? nil : project,
      collectionID: collection.isEmpty ? nil : collection
    )
  }

  /// The Axiom request filter a knowledge source id resolves to.
  ///
  /// Accepts the legacy scopes ("project", "global", "all") as well as the
  /// named-source ids "project:<uuid>" / "collection:<uuid>". Fails closed:
  /// anything unrecognized throws rather than widening to a tenant-wide search,
  /// because an unfiltered search is the one answer no scope should degrade to.
  func filter(for scope: String) throws -> [String: String] {
    if let target = scope.dropping(prefix: "project:") {
      return ["projectId": target]
    }

    if let target = scope.dropping(prefix: "collection:") {
      return ["collectionId": target]
    }

    switch scope {
    case "project":
      guard let projectID else {
        throw ClientError.missingProject
      }
      return ["projectId": projectID]
    case "global":
      guard let collectionID else {
        throw ClientError.missingCollection
      }
      return ["collectionId": collectionID]
    case "all":
      return [:] // tenant-wide search, no filter
    default:
      throw ClientError.invalidScope(scope)
    }
  }

  /// Knowledge snippet texts, most relevant first, formatted "[filename › heading]\ncontent".
  func search(query: String, scope: String, limit: Int) async throws -> [String] {
    struct Hit: Decodable {
      let content: String?
      let heading: String?
      let filename: String?
    }
    struct Payload: Decodable {
      let results: [Hit]?
    }

    var body: [String: Any] = ["query": query, "limit": limit]
    for (key, value) in try filter(for: scope) {
      body[key] = value
    }

    guard let url = URL(string: "\(origin)/api/v1/rag/search") else {
      throw ClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.http(-1, "Invalid response")
    }

    guard (200...299).contains(http.statusCode) else {
      // A 400 on the unfiltered "all" search is not a malformed request but an
      // ambiguous one: the token names several projects and the service will
      // not guess between them. Say that, instead of repeating its wording.
      if http.statusCode == 400, scope == "all", Self.isMissingTarget(data) {
        throw ClientError.notTenantWide
      }

      throw ClientError.http(http.statusCode, Self.errorDetail(from: data))
    }

    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: data)
    } catch {
      throw ClientError.decoding(error.localizedDescription)
    }

    return (payload.results ?? []).compactMap { hit in
      guard let text = hit.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
      }

      let label = [hit.filename, hit.heading]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " › ")

      return label.isEmpty ? text : "[\(label)]\n\(text)"
    }
  }

  /// Whether the response is the API's "name a project or collection" rejection.
  private static func isMissingTarget(_ data: Data) -> Bool {
    guard let text = String(data: data, encoding: .utf8)?.lowercased() else {
      return false
    }

    return text.contains("projectid") && text.contains("collectionid")
  }

  /// Prefers the API envelope's error message ({"ok":false,"error":{"code","message"}})
  /// over dumping the raw response body into user-facing errors.
  private static func errorDetail(from data: Data) -> String {
    struct Envelope: Decodable {
      struct Inner: Decodable {
        let code: String?

        let message: String?
      }

      let error: Inner?
    }

    if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
       let message = envelope.error?.message, !message.isEmpty {
      if let code = envelope.error?.code, !code.isEmpty {
        return "\(message) (\(code))"
      }
      return message
    }
    return String(data: data, encoding: .utf8) ?? ""
  }
}

// MARK: - Helpers

extension String {
  /// The remainder after `prefix`, or nil when the prefix is absent or nothing
  /// follows it — so "project:" is rejected rather than read as an empty target.
  func dropping(prefix: String) -> String? {
    guard hasPrefix(prefix) else {
      return nil
    }

    let target = String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    return target.isEmpty ? nil : target
  }
}
