#!/bin/sh
/usr/bin/sandbox-exec -p "(version 1)
(deny default)
(import \"system.sb\")
(allow file-read*)
(allow process*)
(allow mach-lookup (global-name \"com.apple.lsd.mapdb\"))
(allow mach-lookup (global-name \"com.apple.mobileassetd.v2\"))
(allow file-write*
    (subpath \"/private/tmp\")
    (subpath \"/private/var/tmp\")
    (subpath \"/private/var/folders/f0/zr51nc3x2vd52c93clh7n6_00000gn/T\")
    (subpath \"/private/var/folders/f0/zr51nc3x2vd52c93clh7n6_00000gn/C\")
)
(deny file-write*
    (subpath \"/Users/oli/Projects/nyx.markEdit\")
)
(allow file-write*
    (subpath \"/Users/oli/Projects/nyx.markEdit/build/Build/Intermediates.noindex/BuildToolPluginIntermediates/MarkEdit.output/MarkEditMac/SwiftLint\")
    (subpath \"/private/var/folders/f0/zr51nc3x2vd52c93clh7n6_00000gn/T/TemporaryItems\")
)
" /Users/oli/Projects/nyx.markEdit/build/SourcePackages/artifacts/markedittools/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint lint --strict --config /Users/oli/Projects/nyx.markEdit//.swiftlint.yml --cache-path /Users/oli/Projects/nyx.markEdit/build/Build/Intermediates.noindex/BuildToolPluginIntermediates/MarkEdit.output/MarkEditMac/SwiftLint//cache /Users/oli/Projects/nyx.markEdit/

