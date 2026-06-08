// 
// GeneratedStringSymbols_Localizable.swift
// Auto-Generated symbols for localized strings defined in “Localizable.xcstrings”.
// 

import Foundation

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.atURL(resourceBundle.bundleURL)
#else

private class ResourceBundleClass {}
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.forClass(ResourceBundleClass.self)
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
nonisolated extension LocalizedStringResource {
    /**
     Localized string for key “Evaluate JavaScript with ${content}” in table “Localizable.xcstrings”.
     */
    static var evaluateJavaScriptWith$Content: LocalizedStringResource {
        LocalizedStringResource("Evaluate JavaScript with ${content}", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Localized string for key “Update file with ${content}” in table “Localizable.xcstrings”.
     */
    static var updateFileWith$Content: LocalizedStringResource {
        LocalizedStringResource("Update file with ${content}", table: "Localizable", bundle: resourceBundleDescription)
    }
}