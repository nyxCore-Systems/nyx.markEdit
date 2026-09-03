//
//  SettingsRootViewController.swift
//
//  Created by cyan on 1/26/23.
//

import AppKit
import AppKitExtensions

/**
 Root container for settings view, multi-tab based.
 */
public final class SettingsRootViewController: NSTabViewController {
  private var tabs: [SettingsTabViewController]?
  private var animateChanges = false

  public static func withTabs(_ tabs: [SettingsTabViewController]) -> NSWindowController {
    let contentVC = Self()
    contentVC.tabs = tabs

    let window = NSPanel(contentViewController: contentVC)
    window.styleMask = [.titled, .closable]
    window.collectionBehavior = .moveToActiveSpace

    return NSWindowController(window: window)
  }

  override public func viewDidLoad() {
    super.viewDidLoad()
    tabStyle = .toolbar

    tabs?.forEach {
      addTabViewItem($0.tabViewItem)
    }

    (NSCursor.arrow as NSCursorDeprecated).setOnMouseEntered(true)
    view.addTrackingRect(view.bounds, owner: NSCursor.arrow, userData: nil, assumeInside: true)
  }

  override public func viewDidAppear() {
    super.viewDidAppear()
    view.window?.centerOnScreen()
  }
}

// MARK: - NSTabViewDelegate

extension SettingsRootViewController {
  override public func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    guard let contentVC = tabViewItem?.viewController as? SettingsTabViewController else {
      return
    }

    // Performing in the next run loop has a better visual effect
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      self.view.window?.setFrameSize(CGSize(
        width: 580,
        height: self.contentHeight(for: contentVC)
      ), animated: self.animateChanges && !self.reduceMotion)

      // Enable animations after initial selection
      self.animateChanges = true
    }

    // Mimic the effect of some 1st-party apps, such as Calendar.app,
    // don't use isHidden, it affects the layout.
    if !reduceMotion {
      view.alphaValue = 0
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.view.alphaValue = 1
      }
    }
  }
}

// MARK: - Private

private extension SettingsRootViewController {
  /// Content height for a tab, never taller than what the screen can show.
  ///
  /// `setFrameSize` takes a *content* size and grows it by the titlebar and
  /// toolbar, so the cap has to be computed in content space too. Without the
  /// cap AppKit shrinks the oversized window to fit the screen, and since the
  /// pane below is only reachable by scrolling, the difference is invisible:
  /// the settings simply appear to end early.
  func contentHeight(for contentVC: SettingsTabViewController) -> Double {
    let contentHeight = contentVC.contentView.fittingSize.height
    guard let window = view.window, let screen = window.screen ?? .main else {
      return contentHeight
    }

    let chromeHeight = window.frameRect(forContentRect: .zero).height
    let available = screen.visibleFrame.height - chromeHeight
    return min(contentHeight, max(available, 0))
  }

  var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}
