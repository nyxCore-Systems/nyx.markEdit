//
//  EditorModuleAI.swift
//
//  Bridge module that forwards JS-side AI refactor requests to the
//  app-supplied AIService implementation.
//

import Foundation
import MarkEditCore

public struct AIRefactorResponse: Codable, Equatable, Sendable {
  public var result: String?
  public var error: String?
  /// Non-fatal note about a degraded run — e.g. knowledge retrieval failed and
  /// the rewrite went ahead ungrounded. Presented alongside a result, never
  /// instead of one, so a silent downgrade cannot pass for a grounded answer.
  public var warning: String?

  public init(result: String? = nil, error: String? = nil, warning: String? = nil) {
    self.result = result
    self.error = error
    self.warning = warning
  }
}

public struct AIPersona: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var description: String?
  public var source: String?
  public var circleId: String?
  public var circleName: String?

  public init(
    id: String,
    name: String,
    description: String? = nil,
    source: String? = nil,
    circleId: String? = nil,
    circleName: String? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.source = source
    self.circleId = circleId
    self.circleName = circleName
  }
}

public struct AIPersonaListResponse: Codable, Equatable, Sendable {
  public var personas: [AIPersona]?
  public var error: String?

  public init(personas: [AIPersona]? = nil, error: String? = nil) {
    self.personas = personas
    self.error = error
  }
}

/// One selectable grounding source for AI actions.
///
/// `id` is the routing key the web side hands back. The legacy scope strings
/// ("off", "project", "global", "all") remain valid ids; named sources use
/// "project:<uuid>" / "collection:<uuid>" so the target travels with the id and
/// no second lookup is needed to resolve it.
public struct AIKnowledgeSource: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  /// "off" | "project" | "collection" | "all"
  public var kind: String

  public init(id: String, name: String, kind: String) {
    self.id = id
    self.name = name
    self.kind = kind
  }
}

public struct AIKnowledgeConfig: Codable, Equatable, Sendable {
  public var availableScopes: [String]
  public var defaultScope: String
  public var sources: [AIKnowledgeSource]
  public var defaultSourceId: String

  public init(
    availableScopes: [String],
    defaultScope: String,
    sources: [AIKnowledgeSource] = [],
    defaultSourceId: String = "off"
  ) {
    self.availableScopes = availableScopes
    self.defaultScope = defaultScope
    self.sources = sources
    self.defaultSourceId = defaultSourceId
  }
}

@MainActor
public protocol AIService: AnyObject {
  func isConfigured() async -> Bool
  func refactor(action: AIAction, selection: String, context: String?) async -> AIRefactorResponse
  func listPersonas() async -> AIPersonaListResponse
  func knowledgeConfig() async -> AIKnowledgeConfig
  // swiftlint:disable:next function_parameter_count
  func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> AIRefactorResponse
  func refactorWithPrompt(
    prompt: String,
    selection: String,
    context: String?,
    knowledgeSource: String
  ) async -> AIRefactorResponse
}

public final class EditorModuleAI: NativeModuleAI {
  private let service: AIService

  public init(service: AIService) {
    self.service = service
  }

  public func isConfigured() async -> Bool {
    await service.isConfigured()
  }

  public func refactor(action: AIAction, selection: String, context: String?) async -> String {
    let response = await service.refactor(action: action, selection: selection, context: context)
    return response.jsonEncoded
  }

  public func listPersonas() async -> String {
    let response = await service.listPersonas()
    return response.jsonEncoded
  }

  public func getKnowledgeConfig() async -> String {
    let response = await service.knowledgeConfig()
    return response.jsonEncoded
  }

  // swiftlint:disable:next function_parameter_count
  public func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> String {
    let response = await service.refactorWithPersona(
      personaID: personaID,
      personaName: personaName,
      circleID: circleID,
      selection: selection,
      context: context,
      knowledgeScope: knowledgeScope
    )
    return response.jsonEncoded
  }

  public func refactorWithPrompt(
    prompt: String,
    selection: String,
    context: String?,
    knowledgeSource: String
  ) async -> String {
    let response = await service.refactorWithPrompt(
      prompt: prompt,
      selection: selection,
      context: context,
      knowledgeSource: knowledgeSource
    )
    return response.jsonEncoded
  }
}
