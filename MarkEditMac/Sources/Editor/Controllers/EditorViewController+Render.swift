//
//  EditorViewController+Render.swift
//  MarkEditMac
//
//  Full-document rendered preview (Markdown + Mermaid + KaTeX) with PDF export.
//

import AppKit
import Renderer

private var rendererControllerKey: UInt8 = 0

extension EditorViewController {
  /// Open (or focus) a window that renders the current document with Markdown, mermaid and KaTeX,
  /// and offers a PDF export action.
  func showRenderedPreview() {
    // If a renderer is already open, refresh and focus it instead of opening a second one.
    if let existing = rendererController {
      Task { @MainActor in
        let markdown = await editorText ?? document?.stringValue ?? ""
        existing.update(markdown: markdown)
        existing.window?.makeKeyAndOrderFront(nil)
      }
      return
    }

    Task { @MainActor in
      let markdown = await editorText ?? document?.stringValue ?? ""
      let title = document?.displayName ?? Localized.Renderer.windowTitle
      let baseFilename = (document?.fileURL?.deletingPathExtension().lastPathComponent)
        ?? document?.displayName
        ?? "Document"

      let controller = RendererWindowController(
        markdown: markdown,
        title: "\(Localized.Renderer.windowTitle) – \(title)",
        suggestedFilename: baseFilename,
        localizable: rendererLocalizable
      ) { [weak self] in
        // Synchronous fallback: use the last-known string. The async value is fetched
        // and pushed via `update(markdown:)` right after.
        let cached = self?.document?.stringValue ?? ""
        if let self {
          Task { @MainActor in
            if let latest = await self.editorText {
              self.rendererController?.update(markdown: latest)
            }
          }
        }
        return cached
      }

      // Retain the controller for the lifetime of the editor.
      rendererController = controller

      // Drop the reference once the window closes.
      let token = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: controller.window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.rendererController = nil
        }
      }
      _ = token

      controller.showWindow(nil)
      controller.window?.makeKeyAndOrderFront(nil)
    }
  }
}

// MARK: - Private

private extension EditorViewController {
  var rendererController: RendererWindowController? {
    get {
      objc_getAssociatedObject(self, &rendererControllerKey) as? RendererWindowController
    }
    set {
      objc_setAssociatedObject(self, &rendererControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  var rendererLocalizable: RendererLocalizable {
    RendererLocalizable(
      exportPDF: Localized.Renderer.exportPDF,
      refresh: Localized.Renderer.refresh,
      savePanelTitle: Localized.Renderer.savePanelTitle,
      exportPDFFailed: Localized.Renderer.exportPDFFailed,
      okButton: Localized.Renderer.okButton
    )
  }
}
