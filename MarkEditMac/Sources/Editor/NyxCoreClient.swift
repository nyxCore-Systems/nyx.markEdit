//
//  NyxCoreClient.swift
//  MarkEditMac
//
//  Thin client for the nyxCore MCP endpoint. Speaks stateless JSON-RPC
//  ("tools/call") over HTTP — no initialize handshake or session is required.
//
//  Response envelope: { "result": { "content": [{ "type": "text", "text": "<json>" }] } }
//  where the inner "text" is itself a JSON string that we decode a second time.
//

import Foundation

struct NyxPersona: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let description: String?
}

struct NyxProject: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let description: String?
  let status: String?
}

struct NyxCoreClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case rpc(String)
    case decoding(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid nyxCore endpoint URL."
      case let .http(code, detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "nyxCore request failed: HTTP \(code)" : "nyxCore request failed: \(trimmed)"
      case .rpc(let message):
        return "nyxCore error: \(message)"
      case .decoding(let message):
        return "Could not parse nyxCore response: \(message)"
      }
    }
  }

  let baseURL: String
  let token: String
  let projectID: String?

  /// Client for nyx Persona Studio (get_personas / get_persona_skills), or nil
  /// when nyxCore is disabled or no persona token has been configured.
  @MainActor
  static func personas() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.personaToken ?? "").trimmingCharacters(in: .whitespaces)
    guard !token.isEmpty else {
      return nil
    }

    return Self(baseURL: AppPreferences.NyxCore.personaBaseURL, token: token, projectID: nil)
  }

  /// Client for project knowledge search, or nil when nyxCore is disabled or no
  /// knowledge token has been configured.
  @MainActor
  static func knowledge() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespaces)
    guard !token.isEmpty else {
      return nil
    }

    let project = AppPreferences.NyxCore.projectID.trimmingCharacters(in: .whitespaces)
    return Self(
      baseURL: AppPreferences.NyxCore.knowledgeBaseURL,
      token: token,
      projectID: project.isEmpty ? nil : project
    )
  }

  /// Client for catalog lookups (listing projects), or nil when there is no
  /// MCP token to make them with.
  ///
  /// Uses the persona credentials because the project catalog lives behind the
  /// same MCP endpoint as the personas. A `nyx_pa_` token is Persona Studio
  /// REST and speaks no MCP at all, so it is rejected here rather than sent to
  /// an endpoint that cannot answer.
  @MainActor
  static func directory() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.personaToken ?? "").trimmingCharacters(in: .whitespaces)
    guard !token.isEmpty, !token.hasPrefix(PersonaStudioClient.tokenPrefix) else {
      return nil
    }

    return Self(baseURL: AppPreferences.NyxCore.personaBaseURL, token: token, projectID: nil)
  }

  // MARK: - Tools

  /// Active projects visible to this token, for the Settings pickers.
  ///
  /// Requires a tenant-scoped token; a global-scope one answers with an RPC
  /// error, which surfaces as the reason the list stayed empty.
  func listProjects() async throws -> [NyxProject] {
    struct Payload: Decodable { let projects: [NyxProject] }
    let payload: Payload = try await callTool(
      name: "nyxcore_list_projects",
      arguments: ["status": "active"]
    )

    return payload.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func listPersonas() async throws -> [NyxPersona] {
    struct Payload: Decodable { let personas: [NyxPersona] }
    let payload: Payload = try await callTool(name: "nyxcore_get_personas", arguments: [:])
    return payload.personas
  }

  /// Combined skill prompts for a persona, joined into a single system prompt.
  func personaPrompt(personaID: String) async throws -> String {
    struct Skill: Decodable { let skillPrompt: String? }
    struct Payload: Decodable { let skills: [Skill] }
    let payload: Payload = try await callTool(
      name: "nyxcore_get_persona_skills",
      arguments: ["personaId": personaID, "includePrompt": true]
    )

    return payload.skills
      .compactMap { $0.skillPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }

  /// Knowledge snippet texts relevant to the query, most relevant first.
  func search(query: String, limit: Int) async throws -> [String] {
    struct Metadata: Decodable { let filename: String?; let heading: String? }
    struct Hit: Decodable { let content: String?; let metadata: Metadata? }
    struct Payload: Decodable { let results: [Hit] }

    var arguments: [String: Any] = ["query": query, "limit": limit]
    if let projectID {
      arguments["projectId"] = projectID
    }

    let payload: Payload = try await callTool(name: "nyxcore_search", arguments: arguments)
    return payload.results.compactMap { hit in
      guard let body = hit.content?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
        return nil
      }

      let label = [hit.metadata?.filename, hit.metadata?.heading]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " › ")

      return label.isEmpty ? body : "[\(label)]\n\(body)"
    }
  }

  // MARK: - Transport

  private func callTool<T: Decodable>(name: String, arguments: [String: Any]) async throws -> T {
    guard let url = URL(string: baseURL) else {
      throw ClientError.invalidURL
    }

    let rpc: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": ["name": name, "arguments": arguments],
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: rpc)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.http(-1, "Invalid response")
    }

    guard (200...299).contains(http.statusCode) else {
      throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ClientError.decoding("Malformed JSON-RPC envelope")
    }

    if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
      throw ClientError.rpc(message)
    }

    guard
      let result = root["result"] as? [String: Any],
      let content = result["content"] as? [[String: Any]],
      let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
      let inner = text.data(using: .utf8)
    else {
      throw ClientError.decoding("Missing tool content")
    }

    do {
      return try JSONDecoder().decode(T.self, from: inner)
    } catch {
      throw ClientError.decoding(error.localizedDescription)
    }
  }
}
