//
//  SettingsTabViewController.swift
//
//  Created by cyan on 1/28/23.
//

import AppKit
import SwiftUI

/**
 Wrapper view controller for a settings tab in SettingsRootViewController.
 */
public final class SettingsTabViewController: NSViewController {
  let tabViewItem: NSTabViewItem
  let contentView: NSView
  private let scrollView = NSScrollView(frame: .zero)

  public init(_ rootView: some View, title: String, icon: String) {
    tabViewItem = NSTabViewItem()
    tabViewItem.label = title
    tabViewItem.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
    contentView = NSHostingView(rootView: rootView)
    super.init(nibName: nil, bundle: nil)

    self.title = title
    self.tabViewItem.viewController = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override public func loadView() {
    view = NSView(frame: .zero)
    view.addSubview(scrollView)

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = contentView

    // No bounce when the pane fits, which is the normal case;
    // scrolling only exists for panes too tall for the screen.
    scrollView.verticalScrollElasticity = .none
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    // Rely on SwiftUI view size to have auto-sizing,
    // the window height respects to the contentView height.
    //
    // Pinned to the top only: leaving the bottom free is what lets the
    // document view keep its full intrinsic height and scroll, instead of
    // being squeezed into the clip view and clipped like it used to be.
    contentView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentView.centerXAnchor.constraint(equalTo: scrollView.contentView.centerXAnchor),
      contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
    ])
  }
}
