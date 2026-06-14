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

  public init(result: String? = nil, error: String? = nil) {
    self.result = result
    self.error = error
  }
}

public struct AIPersona: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var description: String?

  public init(id: String, name: String, description: String? = nil) {
    self.id = id
    self.name = name
    self.description = description
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

@MainActor
public protocol AIService: AnyObject {
  func isConfigured() async -> Bool
  func refactor(action: AIAction, selection: String, context: String?) async -> AIRefactorResponse
  func listPersonas() async -> AIPersonaListResponse
  func refactorWithPersona(
    personaID: String,
    personaName: String,
    selection: String,
    context: String?,
    useKnowledge: Bool
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

  public func refactorWithPersona(
    personaID: String,
    personaName: String,
    selection: String,
    context: String?,
    useKnowledge: Bool
  ) async -> String {
    let response = await service.refactorWithPersona(
      personaID: personaID,
      personaName: personaName,
      selection: selection,
      context: context,
      useKnowledge: useKnowledge
    )
    return response.jsonEncoded
  }
}
