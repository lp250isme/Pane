# Pane

iOS / iPadOS Parsec client (fork of hugeBlack/OpenParsec, GPLv3).

## 測試

- `swift test`：Package.swift 只編 `Pane/ParsecUserData.swift`、`Pane/StreamMath.swift`（純邏輯，無 UIKit / Parsec SDK），測試在 `Tests/PaneCoreTests/`。不開模擬器。
- 要測 UI 檔裡的邏輯：先把純函式搬進 `StreamMath.swift`。
- App 本體：`xcodebuild -project Pane.xcodeproj -scheme Pane -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`
