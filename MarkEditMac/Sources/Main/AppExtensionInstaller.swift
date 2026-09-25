//
//  AppExtensionInstaller.swift
//  MarkEditMac
//
//  Installs scripts from the MarkEdit extension registry.
//

import AppKit
import CryptoKit
import AppKitExtensions
import MarkEditKit

/// Handles `markedit://install-extension?id=<id>` links from https://markedit-app.github.io/extensions/.
///
/// Looks the id up in the registry index, asks for confirmation, downloads the script over HTTPS,
/// verifies its pinned sha256 and writes it to scripts/<id>.js. Never installs silently.
@MainActor
enum AppExtensionInstaller {
  static func install(queryDict: [String: String]?) {
    guard let id = queryDict?["id"], isSafeIdentifier(id) else {
      Logger.log(.error, "Invalid install-extension link: \(String(describing: queryDict))")
      return
    }

    Task {
      await install(id: id)
    }
  }
}

// MARK: - Private

private extension AppExtensionInstaller {
  static let registryURL = "https://raw.githubusercontent.com/MarkEdit-app/extensions/main/index.json"

  struct Index: Decodable {
    let extensions: [Entry]
  }

  struct Entry: Decodable {
    let id: String
    let name: String
    let author: String?
    let description: String?
    let latest: Release
  }

  struct Release: Decodable {
    let version: String
    let url: String
    let sha256: String
    let minAppVersion: String?
  }

  enum Failure: Error {
    case notFound
    case incompatible(minAppVersion: String)
    case downloadFailed
    case integrityMismatch
    case writeFailed
  }

  static func install(id: String) async {
    do {
      let entry = try await fetchEntry(id: id)
      if let minAppVersion = entry.latest.minAppVersion, !isAppVersion(atLeast: minAppVersion) {
        throw Failure.incompatible(minAppVersion: minAppVersion)
      }

      guard confirm(entry) else {
        return
      }

      let data = try await download(from: entry.latest.url)
      guard sha256(of: data) == entry.latest.sha256.lowercased() else {
        throw Failure.integrityMismatch
      }

      try write(data: data, id: id)
      presentInstalled(entry)
    } catch {
      Logger.log(.error, "Failed to install extension \(id): \(error)")
      presentError(error, id: id)
    }
  }

  static func fetchEntry(id: String) async throws -> Entry {
    let data = try await download(from: registryURL)
    guard let index = try? JSONDecoder().decode(Index.self, from: data) else {
      throw Failure.downloadFailed
    }

    guard let entry = (index.extensions.first { $0.id == id }) else {
      throw Failure.notFound
    }

    return entry
  }

  /// Downloads over HTTPS, returning the body of a 200 response.
  static func download(from string: String) async throws -> Data {
    guard let url = URL(string: string), url.scheme?.lowercased() == "https" else {
      throw Failure.downloadFailed
    }

    guard let (data, response) = try? await URLSession.shared.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Failure.downloadFailed
    }

    return data
  }

  static func write(data: Data, id: String) throws {
    let directory = AppCustomization.scriptsDirectory.fileURL
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
      try data.write(to: scriptURL(id: id), options: .atomic)
    } catch {
      throw Failure.writeFailed
    }
  }

  static func scriptURL(id: String) -> URL {
    AppCustomization.scriptsDirectory.fileURL.appending(path: "\(id).js", directoryHint: .notDirectory)
  }

  /// Whether `id` is safe as a file name, guarding against path traversal.
  static func isSafeIdentifier(_ id: String) -> Bool {
    guard !id.isEmpty, !id.hasPrefix("."), !id.contains("..") else {
      return false
    }

    return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
  }

  static func isAppVersion(atLeast minAppVersion: String) -> Bool {
    guard let appVersion = Bundle.main.shortVersionString else {
      return false
    }

    return appVersion.compare(minAppVersion, options: .numeric) != .orderedAscending
  }

  static func sha256(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func confirm(_ entry: Entry) -> Bool {
    let replaces = FileManager.default.fileExists(atPath: scriptURL(id: entry.id).path)
    let lines = [
      String(format: Localized.Extensions.versionFormat, entry.latest.version, entry.author ?? "?"),
      entry.description,
      String(format: Localized.Extensions.sourceFormat, entry.latest.url),
      replaces ? Localized.Extensions.replacesNotice : nil,
    ]

    let alert = NSAlert()
    alert.messageText = String(format: Localized.Extensions.confirmTitleFormat, entry.name)
    alert.informativeText = lines.compactMap { $0 }.joined(separator: "\n\n")
    alert.addButton(withTitle: Localized.Extensions.installButton)
    alert.addButton(withTitle: Localized.General.cancel)
    return alert.runModal() == .alertFirstButtonReturn
  }

  static func presentInstalled(_ entry: Entry) {
    let alert = NSAlert()
    alert.messageText = Localized.Extensions.installedTitle
    alert.informativeText = String(format: Localized.Extensions.installedMessageFormat, entry.name)
    alert.runModal()
  }

  static func presentError(_ error: Error, id: String) {
    let message: String = {
      switch error {
      case Failure.notFound:
        return String(format: Localized.Extensions.notFoundFormat, id)
      case Failure.incompatible(let minAppVersion):
        return String(format: Localized.Extensions.incompatibleFormat, minAppVersion)
      default:
        return Localized.Extensions.failedMessage
      }
    }()

    let alert = NSAlert()
    alert.messageText = Localized.Extensions.failedTitle
    alert.informativeText = message
    alert.runModal()
  }
}
