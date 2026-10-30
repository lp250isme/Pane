<p align="center"><img src="OpenParsec/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Pane" width="128"></p>

# Pane — 支援 iPhone Duo 的 Parsec 用戶端

[English](#english) | [繁體中文](#繁體中文)

**Download / 下載**: [Latest release (.ipa)](../../releases/latest) · [All releases](../../releases)

---

## English

An open-source iOS/iPadOS client for Parsec, written in Swift with SwiftUI and the Parsec SDK. Pane is a fork of [hugeBlack/OpenParsec](https://github.com/hugeBlack/OpenParsec), renamed, that adds full iPhone Duo (foldable) support, a native iOS UI and a round of stability fixes.

### What this fork changes

Modified from the upstream project starting October 2026 (GPLv3 §5a notice):

- **iPhone Duo**: fold, unfold, half fold and multiple windows. The picture keeps its aspect ratio (black bars instead of stretching) and stays clear of the hinge.
- **Native UI**: a sidebar for Hosts / Friends / Settings on iOS 17+, settings as a native form, native login and prompts.
- **Stream controls**: a Liquid Glass menu button (iOS 26) opens a native popover with bitrate, display switching, resolution (non-Mac hosts), sound, constant frame rate, pinch to zoom and stats.
- **Mac hosts**: the client never changes the Mac's display resolution, so switching to another monitor (portrait ones included) sticks.
- **Name and look**: renamed to Pane with its own icon and an orange accent in place of the Parsec branding.
- **Fixes**: stretched Metal picture on non-16:9 screens, keyboard hide leaving the picture lifted, a cursor data race, a clean disconnect when the app is killed, and the nightly CI metadata.

### Install

The release `.ipa` is unsigned. Sideload it with AltStore, SideStore, Sideloadly or your own certificate.

### Using it

- **Touch**: pick touchpad or direct touch in Settings. Tap with 3 fingers to bring up the on-screen keyboard. Two fingers scroll or zoom, set in the stream menu.
- **Mouse & keyboard**: USB mice and keyboards are supported.
- **Game controllers**: press any trigger while streaming and Parsec picks the controller up. Set the host up first (virtual USB driver and so on).

### Lag / low bitrate

If the stream lags out of nowhere or the bitrate hardly goes over 10 Mbps, run the network test in Steam Link. Constant lag spikes in that graph point to an Apple Wi-Fi issue that apps can't fix ([discussion](https://github.com/moonlight-stream/moonlight-ios/issues/627)). Moving the router to channel 149 helps. If you can't, power off nearby Apple devices (especially Macs), test again with only the streaming device on, then turn the others back on. The fix can last hours or days.

### Building

Put the Parsec SDK framework in `Frameworks/` (symlink or copy), open `OpenParsec.xcodeproj` and build. CI builds with Xcode 26. The iOS 27 fold APIs compile only with the Swift 6.4 toolchain or newer.

### Credit and license

Based on [OpenParsec](https://github.com/hugeBlack/OpenParsec) by hugeBlack and its contributors. Licensed under the GNU GPL v3, see [LICENSE](LICENSE). Parsec and the Parsec logo are trademarks of their owner. This project is not affiliated with or endorsed by Parsec. The Parsec SDK binary is under Parsec's own terms.

---

## 繁體中文

iOS / iPadOS 上連線 Parsec 的開源用戶端，以 Swift、SwiftUI 與 Parsec SDK 撰寫。Pane 是 [hugeBlack/OpenParsec](https://github.com/hugeBlack/OpenParsec) 的分支並改了名，加入完整的 iPhone Duo（摺疊機）支援、原生 iOS 介面，並修了一輪穩定性問題。

### 這個分支改了什麼

2026 年 10 月起由上游修改而來（GPLv3 §5a 修改聲明）：

- **iPhone Duo**：支援展開、闔上、半摺與多視窗。畫面維持原比例（加黑邊、不拉伸），並避開轉軸。
- **原生介面**：iOS 17+ 用側邊欄切換主機 / 好友 / 設定，設定改成原生表單，登入與提示框也改成原生樣式。
- **串流控制**：選單按鈕在 iOS 26 是 Liquid Glass，點開是原生 popover，內有碼率、切換螢幕、解析度（非 Mac 主機）、聲音、固定幀率、雙指縮放與連線資訊。
- **Mac 主機**：不會改動 Mac 的螢幕解析度，所以切到其他螢幕（包括直立螢幕）會留在那裡，不會彈回主螢幕。
- **名稱與外觀**：改名為 Pane，換成自己的 icon，並以橘色強調色取代 Parsec 的品牌元素。
- **修正**：非 16:9 螢幕上 Metal 畫面被拉伸、收鍵盤後畫面沒歸位、游標資料跨執行緒競態、App 被關掉時沒有好好斷線，以及 nightly CI 的版本資訊錯誤。

### 安裝

Release 裡的 `.ipa` 沒有簽章，請用 AltStore、SideStore、Sideloadly 或自己的憑證側載。

### 使用方式

- **觸控**：在設定裡選觸控板模式或直接觸控模式。三指點一下叫出螢幕鍵盤。雙指拿來捲動還是縮放，在串流選單裡切換。
- **滑鼠與鍵盤**：支援 USB 滑鼠與鍵盤。
- **遊戲手把**：串流時按任一板機鍵，Parsec 就會抓到手把。使用前要先把主機端設好（安裝虛擬 USB 驅動等）。

### 卡頓 / 碼率上不去

如果串流莫名卡頓，或碼率幾乎不超過 10 Mbps，先用 Steam Link 跑網路測試。圖上如果一直有延遲尖峰，就是 Apple Wi-Fi 的問題，App 這邊修不了（[相關討論](https://github.com/moonlight-stream/moonlight-ios/issues/627)）。把路由器頻道改到 149 會有幫助。改不了的話，把附近的 Apple 裝置（尤其是 Mac）都關機，只開要串流的裝置再測一次，沒問題了再把其他裝置開回來，通常可以維持幾小時到幾天。

### 自行編譯

把 Parsec SDK framework 放進 `Frameworks/`（symlink 或複製），打開 `OpenParsec.xcodeproj` 編譯即可。CI 用 Xcode 26 編譯，iOS 27 的摺疊 API 只有 Swift 6.4 以上的工具鏈才會編進去。

### 致謝與授權

本專案基於 hugeBlack 與其他貢獻者的 [OpenParsec](https://github.com/hugeBlack/OpenParsec)，以 GNU GPL v3 授權，見 [LICENSE](LICENSE)。Parsec 名稱與標誌是其所有者的商標，本專案與 Parsec 官方沒有關聯，也未經其背書。Parsec SDK 二進位檔適用 Parsec 自己的條款。
