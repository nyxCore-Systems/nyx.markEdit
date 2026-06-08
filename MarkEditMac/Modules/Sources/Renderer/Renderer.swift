//
//  Renderer.swift
//
//  Full-document Markdown preview window with mermaid + KaTeX support
//  and a "Save as PDF" action.
//

import AppKit
import AppKitExtensions
import WebKit
import MarkEditKit

public struct RendererLocalizable: Sendable {
  let exportPDF: String
  let refresh: String
  let savePanelTitle: String
  let exportPDFFailed: String
  let okButton: String

  public init(
    exportPDF: String,
    refresh: String,
    savePanelTitle: String,
    exportPDFFailed: String,
    okButton: String
  ) {
    self.exportPDF = exportPDF
    self.refresh = refresh
    self.savePanelTitle = savePanelTitle
    self.exportPDFFailed = exportPDFFailed
    self.okButton = okButton
  }
}

/// Window controller that renders a Markdown document to HTML in a WKWebView
/// and offers a toolbar to refresh or export as PDF.
@MainActor
public final class RendererWindowController: NSWindowController {
  private enum Constants {
    // A4 (210mm) ≈ 793 px at 96dpi. Add canvas margin (~24px) on each side, plus a
    // bit of breathing room, so the entire paper is always visible on first open.
    static let defaultWidth: CGFloat = 880
    static let defaultHeight: CGFloat = 1000
    static let minimumWidth: CGFloat = 820
    static let minimumHeight: CGFloat = 480
  }

  private enum ToolbarIdentifiers {
    static let toolbar = NSToolbar.Identifier("app.markedit.renderer.toolbar")
    static let exportPDF = NSToolbarItem.Identifier("app.markedit.renderer.exportPDF")
    static let refresh = NSToolbarItem.Identifier("app.markedit.renderer.refresh")
  }

  private let suggestedFilename: String
  private let localizable: RendererLocalizable
  private var refreshHandler: (@MainActor () -> String)?
  private var isRendered = false

  private lazy var webView: WKWebView = {
    let controller = WKUserContentController()
    controller.add(MessageHandler(host: self), name: "bridge")

    let config = WKWebViewConfiguration()
    config.userContentController = controller

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsMagnification = true
    return webView
  }()

  /// Create a renderer window for the given Markdown.
  /// - Parameters:
  ///   - markdown: initial Markdown source.
  ///   - title: window title (e.g., document name).
  ///   - suggestedFilename: filename hint used in the PDF save panel (without extension).
  ///   - localizable: localized strings for toolbar / panel labels.
  ///   - refreshHandler: optional closure that returns the latest Markdown when "Refresh" is clicked.
  public init(
    markdown: String,
    title: String,
    suggestedFilename: String,
    localizable: RendererLocalizable,
    refreshHandler: (@MainActor () -> String)? = nil
  ) {
    self.suggestedFilename = suggestedFilename
    self.localizable = localizable
    self.refreshHandler = refreshHandler

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: Constants.defaultWidth, height: Constants.defaultHeight),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.minSize = CGSize(width: Constants.minimumWidth, height: Constants.minimumHeight)
    window.titleVisibility = .visible
    window.isReleasedWhenClosed = false
    window.center()

    super.init(window: window)
    window.delegate = self

    let toolbar = NSToolbar(identifier: ToolbarIdentifiers.toolbar)
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    let container = NSView(frame: .zero)
    container.autoresizingMask = [.width, .height]
    webView.frame = container.bounds
    webView.autoresizingMask = [.width, .height]
    container.addSubview(webView)
    window.contentView = container

    load(markdown: markdown)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Replace the rendered Markdown.
  public func update(markdown: String) {
    load(markdown: markdown)
  }
}

// MARK: - Loading

private extension RendererWindowController {
  func load(markdown: String) {
    isRendered = false

    guard let template = Self.template else {
      Logger.assertFail("Missing Renderer/index.html resource")
      return
    }

    struct Wrapper: Encodable {
      let markdown: String
    }
    let payload = Wrapper(markdown: markdown).jsonEncoded
    let html = template.replacingOccurrences(of: "\"{{DATA}}\"", with: payload)

    webView.loadHTMLString(html, baseURL: nil)
  }

  static let template: String? = {
    guard let url = Bundle.module.url(forResource: "index", withExtension: "html") else {
      return nil
    }

    return try? String(contentsOf: url, encoding: .utf8)
  }()
}

// MARK: - Actions

private extension RendererWindowController {
  @objc func refreshAction(_ sender: Any?) {
    guard let refreshHandler else { return }
    let updated = refreshHandler()
    update(markdown: updated)
  }

  @objc func exportPDFAction(_ sender: Any?) {
    let panel = NSSavePanel()
    panel.title = localizable.savePanelTitle
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = "\(suggestedFilename).pdf"
    panel.canCreateDirectories = true

    let parentWindow = window ?? NSApp.keyWindow
    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let destination = panel.url else { return }
      self?.writePDF(to: destination)
    }

    if let parentWindow {
      panel.beginSheetModal(for: parentWindow, completionHandler: completion)
    } else {
      completion(panel.runModal())
    }
  }

  func writePDF(to destination: URL) {
    // A4 portrait in points (1pt = 1/72 in). 1mm ≈ 2.8346 pt.
    let printInfo = NSPrintInfo()
    printInfo.paperSize = NSSize(width: 595.276, height: 841.89)
    printInfo.orientation = .portrait
    printInfo.scalingFactor = 1.0
    printInfo.topMargin = 56.7    // 20mm
    printInfo.bottomMargin = 62.4 // 22mm
    printInfo.leftMargin = 51.0   // 18mm
    printInfo.rightMargin = 51.0  // 18mm
    printInfo.horizontalPagination = .automatic
    printInfo.verticalPagination = .automatic
    printInfo.isHorizontallyCentered = false
    printInfo.isVerticallyCentered = false
    printInfo.jobDisposition = .save

    // Direct the print job to save as PDF at our destination URL.
    let attrs = printInfo.dictionary()
    attrs[NSPrintInfo.AttributeKey.jobSavingURL] = destination as NSURL

    let op = webView.printOperation(with: printInfo)
    op.showsPrintPanel = false
    op.showsProgressPanel = false
    op.view?.frame = NSRect(x: 0, y: 0, width: 595.276, height: 841.89)

    if let parent = window {
      op.runModal(for: parent, delegate: nil, didRun: nil, contextInfo: nil)
    } else {
      op.run()
    }
  }

  func showErrorAlert(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = localizable.exportPDFFailed
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: localizable.okButton)
    alert.runModal()
  }
}

// MARK: - NSToolbarDelegate

extension RendererWindowController: NSToolbarDelegate {
  public func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case ToolbarIdentifiers.exportPDF:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = localizable.exportPDF
      item.toolTip = localizable.exportPDF
      item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: localizable.exportPDF)
      item.isBordered = true
      item.target = self
      item.action = #selector(exportPDFAction(_:))
      return item

    case ToolbarIdentifiers.refresh:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = localizable.refresh
      item.toolTip = localizable.refresh
      item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: localizable.refresh)
      item.isBordered = true
      item.target = self
      item.action = #selector(refreshAction(_:))
      item.isEnabled = refreshHandler != nil
      return item

    default:
      return nil
    }
  }

  public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    var items: [NSToolbarItem.Identifier] = [.flexibleSpace]
    if refreshHandler != nil {
      items.append(ToolbarIdentifiers.refresh)
    }
    items.append(ToolbarIdentifiers.exportPDF)
    return items
  }

  public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace, .space, ToolbarIdentifiers.refresh, ToolbarIdentifiers.exportPDF]
  }
}

// MARK: - NSWindowDelegate

extension RendererWindowController: NSWindowDelegate {
  public func windowWillClose(_ notification: Notification) {
    // Drop the closure so the host controller can be released.
    refreshHandler = nil
  }
}

// MARK: - WKScriptMessageHandler

private extension RendererWindowController {
  func handleBridgeMessage(_ body: Any) {
    if let dict = body as? [String: Any], dict["event"] as? String == "ready" {
      isRendered = true
    }
  }

  // Avoid retain cycles by hopping through a weak host.
  final class MessageHandler: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    private weak var host: RendererWindowController?

    init(host: RendererWindowController?) {
      self.host = host
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      let body = message.body
      Task { @MainActor in
        host?.handleBridgeMessage(body)
      }
    }
  }
}
