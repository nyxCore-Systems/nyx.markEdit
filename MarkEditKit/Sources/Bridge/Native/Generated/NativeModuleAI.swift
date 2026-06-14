//
//  NativeModuleAI.swift
//
//  Generated using https://github.com/microsoft/ts-gyb
//
//  Don't modify this file manually, it's auto generated.
//
//  To make changes, edit template files under /CoreEditor/src/@codegen

import Foundation
import MarkEditCore

@MainActor
public protocol NativeModuleAI: NativeModule {
  func isConfigured() async -> Bool
  func refactor(action: AIAction, selection: String, context: String?) async -> String
  func listPersonas() async -> String
  func refactorWithPersona(personaID: String, personaName: String, selection: String, context: String?, useKnowledge: Bool) async -> String
}

public extension NativeModuleAI {
  var bridge: NativeBridge { NativeBridgeAI(self) }
}

@MainActor
final class NativeBridgeAI: NativeBridge {
  static let name = "ai"
  lazy var methods: [String: NativeMethod] = [
    "isConfigured": { [weak self] in
      await self?.isConfigured(parameters: $0)
    },
    "refactor": { [weak self] in
      await self?.refactor(parameters: $0)
    },
    "listPersonas": { [weak self] in
      await self?.listPersonas(parameters: $0)
    },
    "refactorWithPersona": { [weak self] in
      await self?.refactorWithPersona(parameters: $0)
    },
  ]

  private let module: NativeModuleAI
  private lazy var decoder = JSONDecoder()

  init(_ module: NativeModuleAI) {
    self.module = module
  }

  private func isConfigured(parameters: Data) async -> Result<Any?, Error>? {
    let result = await module.isConfigured()
    return .success(result)
  }

  private func refactor(parameters: Data) async -> Result<Any?, Error>? {
    struct Message: Decodable {
      var action: AIAction
      var selection: String
      var context: String?
    }

    let message: Message
    do {
      message = try decoder.decode(Message.self, from: parameters)
    } catch {
      Logger.assertFail("Failed to decode parameters: \(parameters)")
      return .failure(error)
    }

    let result = await module.refactor(action: message.action, selection: message.selection, context: message.context)
    return .success(result)
  }

  private func listPersonas(parameters: Data) async -> Result<Any?, Error>? {
    let result = await module.listPersonas()
    return .success(result)
  }

  private func refactorWithPersona(parameters: Data) async -> Result<Any?, Error>? {
    struct Message: Decodable {
      var personaID: String
      var personaName: String
      var selection: String
      var context: String?
      var useKnowledge: Bool
    }

    let message: Message
    do {
      message = try decoder.decode(Message.self, from: parameters)
    } catch {
      Logger.assertFail("Failed to decode parameters: \(parameters)")
      return .failure(error)
    }

    let result = await module.refactorWithPersona(personaID: message.personaID, personaName: message.personaName, selection: message.selection, context: message.context, useKnowledge: message.useKnowledge)
    return .success(result)
  }
}

public enum AIAction: String, Codable {
  case improve = "improve"
  case shorten = "shorten"
  case expand = "expand"
  case fixGrammar = "fixGrammar"
  case toneProfessional = "toneProfessional"
  case toneCasual = "toneCasual"
  case toneFriendly = "toneFriendly"
  case toneAcademic = "toneAcademic"
}
