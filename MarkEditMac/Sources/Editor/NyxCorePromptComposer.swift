//
//  NyxCorePromptComposer.swift
//  MarkEditMac
//
//  Pure prompt assembly for nyxCore persona-driven rewrites. No I/O, so it is
//  straightforward to reason about and unit-test in isolation.
//

import Foundation

enum NyxCorePromptComposer {
  /// Shared editor contract: stay a precise Markdown editor and output only the
  /// rewritten passage. Mirrors the system prompt used by the standard refactor.
  static let editorContract = """
  You are a precise text editor for Markdown documents. Rewrite the passage the \
  user provides. Output only the rewritten passage — no preamble, no explanation, \
  no quoting, no surrounding code fences. Preserve the original Markdown formatting \
  (inline code, links, bold/italic markers, list markers, heading levels). Match \
  the language of the selection.
  """

  /// Contract for a user-supplied instruction. Same output discipline as the
  /// canned actions, but the instruction — not a fixed verb — decides what
  /// happens, so language and formatting rules yield to it when it says so.
  static let customInstructionContract = """
  You are a precise text editor for Markdown documents. The user gives you a passage \
  and an instruction describing what to do with it. Follow the instruction exactly and \
  apply it to the passage. Output only the resulting passage — no preamble, no \
  explanation, no quoting, no surrounding code fences. Preserve the original Markdown \
  formatting (inline code, links, bold/italic markers, list markers, heading levels) and \
  the language of the selection, unless the instruction asks for something else. Never \
  answer the instruction as a question; always return the edited passage.
  """

  /// Builds the user message for a free-form instruction: the instruction, any
  /// grounding knowledge, the surrounding context, then the passage.
  ///
  /// Knowledge is labelled as retrieved source material rather than as part of
  /// the instruction, so an instruction like "use the Axiom facts" cannot be
  /// answered from the model's own priors without the retrieval having happened.
  static func customUserPrompt(
    instruction: String,
    selection: String,
    context: String?,
    knowledge: [String]
  ) -> String {
    var parts: [String] = []
    parts.append("Instruction: \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))")

    let snippets = knowledge
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if snippets.isEmpty {
      parts.append(
        "No knowledge base passages were retrieved. If the instruction asks you to use them, "
          + "edit the passage using only what it already says and do not invent sources or facts."
      )
    } else {
      let joined = snippets.joined(separator: "\n\n---\n\n")
      parts.append("Retrieved knowledge base passages (ground the edit in these — do not quote verbatim):\n\(joined)")
    }

    if let context, !context.isEmpty, context != selection {
      parts.append("Surrounding context (for style only — do not rewrite this):\n\(context)")
    }

    parts.append("Passage to edit:\n\(selection)")
    return parts.joined(separator: "\n\n")
  }

  /// Layers the persona's voice on top of the editor contract to form the system prompt.
  static func systemPrompt(personaName: String, personaPrompt: String) -> String {
    let persona = personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !persona.isEmpty else {
      return editorContract
    }

    return """
    \(editorContract)

    Adopt the voice, perspective, and expertise of "\(personaName)". Apply the \
    following guidance while rewriting, but never describe it or mention the persona:

    \(persona)
    """
  }

  /// Builds the user message: instruction + optional grounding knowledge +
  /// optional surrounding context + the passage to rewrite.
  static func userPrompt(selection: String, context: String?, knowledge: [String]) -> String {
    var parts: [String] = []
    parts.append("Rewrite the passage in the persona's voice. Keep the original meaning and intent.")

    let snippets = knowledge
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !snippets.isEmpty {
      let joined = snippets.joined(separator: "\n\n---\n\n")
      parts.append("Relevant project knowledge (use to ground the rewrite — do not quote verbatim):\n\(joined)")
    }

    if let context, !context.isEmpty, context != selection {
      parts.append("Surrounding context (for style only — do not rewrite this):\n\(context)")
    }

    parts.append("Passage to rewrite:\n\(selection)")
    return parts.joined(separator: "\n\n")
  }
}
