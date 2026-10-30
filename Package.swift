// swift-tools-version: 6.0
// Unit tests only: `swift test` compiles the pure logic files below on the Mac, no simulator.
// The app itself still builds from Pane.xcodeproj; this package takes no part in the IPA.
// ponytail: only files without UIKit or the Parsec SDK; move a pure function into one of them to test it.
import PackageDescription

let package = Package(
	name: "PaneCore",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "PaneCore",
			path: "Pane",
			// the app's resources and C files sit in the same folder; keep SwiftPM away from them
			exclude: ["Assets.xcassets", "Base.lproj", "Info.plist", "Localizable.xcstrings", "Pane-Bridging-Header.h", "Preview Content", "audio.c", "audio.h"],
			sources: ["ParsecUserData.swift", "StreamMath.swift"],
			swiftSettings: [.swiftLanguageMode(.v5)]
		),
		.testTarget(name: "PaneCoreTests", dependencies: ["PaneCore"], path: "Tests/PaneCoreTests",
					swiftSettings: [.swiftLanguageMode(.v5)]),
	]
)
