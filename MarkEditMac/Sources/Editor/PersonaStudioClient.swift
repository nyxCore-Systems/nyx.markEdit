//
//  PersonaStudioClient.swift
//  MarkEditMac
//
//  REST client for nyx Persona Studio (nyx_pa_ tokens). Persona Studio does
//  NOT speak the MCP protocol: personas are listed via GET /api/v1/persona/list
//  and rewrites run server-side via POST /api/v1/persona/chat (the LLM call is
//  billed in nyxCore; no local Anthropic key is involved).
//

import Foundation

struct StudioPersona: Sendable {
  let id: String
  let name: String
  let description: String?
  let circleID: String
  let circleName: String
}

struct PersonaStudioClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case api(String, String)
    case decoding(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid Persona Studio endpoint URL."
      case let .http(code, detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Persona Studio request failed: HTTP \(code)" : "Persona Studio request failed: \(trimmed)"
      case let .api(code, message):
        return Self.friendlyMessage(code: code, message: message)
      case .decoding(let message):
        return "Could not parse Persona Studio response: \(message)"
      }
    }

    static func friendlyMessage(code: String, message: String) -> String {
      switch code {
      case "UNAUTHORIZED":
        return "Persona Studio token was rejected. Check the token in Settings → AI."
      case "BUDGET_EXCEEDED":
        return "Persona Studio monthly budget exceeded."
      case "FORBIDDEN":
        return "This token is not allowed to use that persona or circle."
      case "NOT_FOUND":
        return "Persona or circle not found — is the circle published?"
      case "RATE_LIMITED":
        return "Persona Studio rate limit reached. Try again in a minute."
      default:
        return "Persona Studio error: \(message)"
      }
    }
  }

  static let tokenPrefix = "nyx_pa_"

  let origin: String
  let token: String

  /// Client for Persona Studio, or nil when nyxCore is disabled or the persona
  /// token is not a Persona Studio (nyx_pa_) token.
  @MainActor
  static func current() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.personaToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.hasPrefix(tokenPrefix) else {
      return nil
    }

    guard let origin = origin(from: AppPreferences.NyxCore.personaBaseURL) else {
      return nil
    }

    return Self(origin: origin, token: token)
  }

  /// "https://nyxcore.cloud/api/v1/mcp" → "https://nyxcore.cloud". Users keep
  /// their existing endpoint setting; REST paths are derived from the origin.
  static func origin(from urlString: String) -> String? {
    guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host else {
      return nil
    }

    let port = url.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
  }

  // MARK: - Endpoints

  func listPersonas() async throws -> [StudioPersona] {
    struct Member: Decodable {
      let id: String
      let name: String
      let description: String?
    }
    struct Circle: Decodable {
      let id: String
      let name: String
      let personas: [Member]
    }
    struct Payload: Decodable {
      let circles: [Circle]?
    }

    let payload: Payload = try await send(path: "/api/v1/persona/list", method: "GET", body: nil)
    return (payload.circles ?? []).flatMap { circle in
      circle.personas.map { member in
        StudioPersona(
          id: member.id,
          name: member.name,
          description: member.description,
          circleID: circle.id,
          circleName: circle.name
        )
      }
    }
  }

  /// One-shot persona rewrite. The persona's own system prompt is built
  /// server-side; our editor contract travels as a supplementary system message.
  func chat(personaID: String, circleID: String?, system: String, user: String, maxTokens: Int) async throws -> String {
    struct Payload: Decodable {
      let content: String?
    }

    var body: [String: Any] = [
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user],
      ],
      "personaId": personaID,
      "maxTokens": min(8192, max(1, maxTokens)),
      "useSkills": true,
    ]
    if let circleID {
      body["circleId"] = circleID
    }

    let payload: Payload = try await send(path: "/api/v1/persona/chat", method: "POST", body: body)
    guard let content = payload.content, !content.isEmpty else {
      throw ClientError.decoding("Empty chat content")
    }

    return content
  }

  // MARK: - Transport

  // The API wraps errors as { ok: false, error: { code, message } } with a
  // matching non-2xx status; prefer the structured message when present.
  // (Declared outside `send` — Swift does not allow nested types in a generic function.)
  private struct APIEnvelopeError: Decodable {
    struct Inner: Decodable {
      let code: String
      let message: String
    }

    let error: Inner?
  }

  private func send<T: Decodable>(path: String, method: String, body: [String: Any]?) async throws -> T {
    guard let url = URL(string: "\(origin)\(path)") else {
      throw ClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.http(-1, "Invalid response")
    }

    guard (200...299).contains(http.statusCode) else {
      if let envelope = try? JSONDecoder().decode(APIEnvelopeError.self, from: data), let inner = envelope.error {
        throw ClientError.api(inner.code, inner.message)
      }
      throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw ClientError.decoding(error.localizedDescription)
    }
  }
}
