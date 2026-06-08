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

@MainActor
public protocol AIService: AnyObject {
  func isConfigured() async -> Bool
  func refactor(action: AIAction, selection: String, context: String?) async -> AIRefactorResponse
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
}
