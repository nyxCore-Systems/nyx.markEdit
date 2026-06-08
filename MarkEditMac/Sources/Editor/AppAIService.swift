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

    let prompt = buildPrompt(action: action, selection: selection, context: context)
    let body: [String: Any] = [
      "model": AppPreferences.AI.model,
      "max_tokens": AppPreferences.AI.maxTokens,
      "system": Self.systemPrompt,
      "messages": [
        [
          "role": "user",
          "content": prompt,
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

// MARK: - Helpers

private extension String {
  func trimmingTrailingSlash() -> String {
    hasSuffix("/") ? String(dropLast()) : self
  }
}
