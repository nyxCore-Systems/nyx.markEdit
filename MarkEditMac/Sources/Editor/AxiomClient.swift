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

struct AxiomClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case missingProject
    case missingCollection
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

    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespaces)
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
    switch scope {
    case "project":
      guard let projectID else {
        throw ClientError.missingProject
      }
      body["projectId"] = projectID
    case "global":
      guard let collectionID else {
        throw ClientError.missingCollection
      }
      body["collectionId"] = collectionID
    default:
      break // "all": tenant-wide search, no filter
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
      throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
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
}
