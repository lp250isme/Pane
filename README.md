<p align="center"><img src="Pane/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Pane" width="128"></p>

# Pane — 支援 iPhone Duo 的 Parsec 用戶端

[English](#english) | [繁體中文](#繁體中文)

**Download / 下載**: [Latest release (.ipa)](../../releases/latest) · [All releases](../../releases)

---

## English

Pane is an open-source iOS / iPadOS client for [Parsec](https://parsec.app) by kv, written in Swift with SwiftUI and the Parsec SDK. It lets you stream and control your computer from an iPhone, iPad or iPhone Duo. It started as a fork of [hugeBlack/OpenParsec](https://github.com/hugeBlack/OpenParsec) and adds foldable support, a native iOS interface and many fixes.

### Features

**iPhone Duo and foldables**
- Fold, unfold, half fold and multiple windows are all handled.
- The picture keeps the host's aspect ratio, with black bars instead of stretching, and stays clear of the hinge.
- The main screen fills the Duo's status column correctly.

**Native iOS interface**
- iOS 17 and later: a sidebar for Hosts, Friends and Settings, shown only while you are not streaming.
- Settings is a native grouped form. Login, two-factor prompts and connection prompts are native too.
- A black-and-white look in light and dark themes, following the system setting. The app icon has its own light, dark and tinted versions.
- English and Traditional Chinese, following the device language. You can also pick one per app in iOS Settings.

**Stream menu**
Tap the floating button (Liquid Glass on iOS 26) to open a native popover with:
- **Resolution**, only when the host is not a Mac.
- **Bitrate**, for this stream only. Host Default goes back to what the host uses. The saved default lives in Settings.
- **Switch Display**, when the host has more than one monitor.
- Sound, Constant Frame Rate, Pinch to Zoom and Show Stats toggles.
- Hide Buttons and Disconnect.

You can also open the menu by swiping in from the screen edge (set in Settings > Menu Edge Swipe).

**Trackpad below the picture**
In portrait, and on the lower half of a half-folded iPhone Duo, the picture sits at the top and the space below becomes a large trackpad that works like a Mac's:

| Gesture | Does |
|---|---|
| One finger | Move the pointer; a flick keeps gliding |
| Tap | Left click |
| Press and hold, then move | Drag (holds the left button) |
| Two finger tap | Right click |
| Two finger move | Scroll, up and down or sideways |
| Two finger pinch | Zoom the picture above |
| Three finger tap | Show or hide the keyboard |
| Three or four finger swipe up | Mission Control (Windows: Task View) |
| Three or four finger swipe down | App Exposé (Windows: show desktop) |
| Three or four finger swipe left / right | Move between Spaces (Windows: virtual desktops) |
| Four finger spread | Show Desktop |
| Four finger pinch | Spotlight (Windows: Start) |

**Three Finger Drag** (Settings, off by default) matches the Mac's Accessibility > Pointer Control > Trackpad Options > Dragging Style. Pane can't read that setting from the Mac, so set both the same. When it's on, three fingers hold the left button and drag, and the swipes above move to four fingers.

A toolbar under the trackpad holds the stream menu, Mission Control, Show Desktop and the keyboard, so nothing covers the picture. Fingers show as soft lights on the glass and each multi-finger gesture briefly names what it did.

With the keyboard up, the iPhone keyboard takes the lower part and a row of Mac keys sits above it: Esc, ⌃, ⌥, ⌘, ⇧, Tab, F1 to F12, the arrows and Delete, plus ⌘C, ⌘V, ⌘X, ⌘Z and ⌘A (Ctrl on a Windows host), and ⌘Tab, ⌘Space, ⌘H, ⌘⇧3 and ⌘⇧4, which iPadOS keeps for itself when typed on a hardware keyboard. A modifier stays down until the next key. Half open, the keys move into the keyboard's own top bar on the lower half when the system shows one; otherwise they stay above the keyboard. Turn the trackpad off in Settings > Trackpad Below the Picture.

The phone's own keyboard language is what the host gets. Switch to Zhuyin, Pinyin or Kana with the globe key and type as usual: each word shows above the keyboard while you compose it and goes to the host as text once picked, whatever input source the Mac is on. Text goes through the host's clipboard and a paste, and once the host has shared its clipboard (it does when you copy something there), that text is put back afterwards. The host's Parsec setting `app_copy_paste` must stay on (it is by default). Korean isn't supported yet.

**Mac hosts**
A Mac host streams each monitor at its own resolution, so Pane hides the resolution choice and always asks for the host's own size. Switching to a second monitor on a Mac host is still being worked on: on some setups the host goes back to the main monitor a few seconds later.

### Requirements

- iOS / iPadOS 15 or later. The sidebar needs iOS 17, Liquid Glass needs iOS 26, and the foldable APIs need iOS 27.
- A Parsec account and a computer running the Parsec host app.

### Install

The release `.ipa` is unsigned. Sideload it with one of these:
1. **AltStore / SideStore**: open the app, go to My Apps, tap +, and choose `Pane.ipa`.
2. **Sideloadly**: connect the device to a computer, drag `Pane.ipa` in and sign with your Apple ID.
3. **Your own certificate**: re-sign the `.ipa` with your developer certificate.

The bundle id is the same as OpenParsec's, so Pane installs over an existing OpenParsec and keeps your sign-in.

### Using Pane

1. Sign in with your Parsec account. Accounts with two-factor authentication get a code prompt.
2. Pick a computer in Hosts and tap Connect. If the host has to approve guests, Pane waits for the approval.
3. While streaming:

| Gesture | Touchpad mode | Direct touch mode |
|---|---|---|
| One finger tap | Left click | Left click where you tap |
| One finger drag | Move the cursor | Drag at your finger |
| Long press, then drag | Hold the left button (drag files and windows) | — |
| Two finger tap | Right click | Right click |
| Two finger drag | Scroll | Scroll |
| Pinch | Zoom the picture (when Pinch to Zoom is on) | Same |
| Three finger tap | Show or hide the keyboard | Same |

- The on-screen keyboard has an extra row of Mac keys: Esc, ⌃, ⌥, ⌘, ⇧, Tab, F1 to F12, the arrows and Delete. When the keyboard covers part of the picture, drag the handle to move the picture into view.
- **Mouse and keyboard**: USB and Bluetooth mice and keyboards work, Magic Keyboard included. A hardware keyboard types to the host as soon as it's attached; the keyboard button then brings up only the Mac key row. With a mouse or trackpad attached, the trackpad below the picture steps aside and the picture fills the screen. Option can be mapped to Command (Settings > Option Key as Command).
- **Game controllers**: press any trigger while streaming and Parsec picks up the controller. Set up the host first, for example by installing its virtual USB driver.
- **Picture in Picture** keeps the stream in a floating window when you leave the app (Settings > Picture in Picture).
- **Auto Reconnect** quietly reconnects after a network drop. Switching between Wi-Fi and cellular reconnects right away; with no network at all (an elevator, a tunnel) it waits for the network to come back, then keeps trying for up to two minutes. A quick trip to another app comes back to a live stream; after a longer one, Pane reconnects when you return.
- **On cellular or Low Data Mode**, if you haven't picked a bitrate, the stream is capped at 10 Mbps.

### Settings

| Section | What you can change |
|---|---|
| Touch & Mouse | Touch mode, which finger right-clicks, pointer speed, cursor size, scroll speed, reverse scrolling, pinch to zoom, trackpad below the picture |
| Keyboard | Keyboard button, Option as Command |
| Video | Renderer (Metal or OpenGL), resolution (non-Mac hosts), bitrate, frame rate, constant frame rate, codec (H.264 or H.265) |
| During a Stream | Stream stats, menu button, menu edge swipe, hide the status bar, Picture in Picture, start muted |
| Connection | Auto reconnect, reconnect error prompts |

### Troubleshooting

**The stream lags, or the bitrate stays under 10 Mbps**
Run the network test in Steam Link. Constant lag spikes in the graph point to an Apple Wi-Fi issue that apps can't fix ([discussion](https://github.com/moonlight-stream/moonlight-ios/issues/627)). Moving the router to channel 149 helps. If you can't, power off nearby Apple devices (Macs especially), test again with only the streaming device on, and then turn the others back on. The improvement can last hours or days.

**Switching display jumps back to the main monitor**
This is a known issue with some Mac hosts and is being investigated. The app writes `diagnostics.log`, which you can find in the Files app under On My iPhone > Pane. Attaching it to an issue helps.

**The picture has black bars**
This is intended. Pane keeps the host's aspect ratio instead of stretching it or changing the host's resolution.

### Building from source

1. Put the Parsec SDK framework in `Frameworks/` (copy it or symlink it).
2. Open `Pane.xcodeproj` and build the `Pane` scheme.
3. CI builds with Xcode 26. The iOS 27 foldable code compiles only with the Swift 6.4 toolchain or newer.

Run the unit tests with `swift test` (no simulator needed). To regenerate the app icon, run `swift scripts/make-icon.swift Pane/Assets.xcassets`. Strings live in `Pane/Localizable.xcstrings`.

### Changes from OpenParsec

Modified from hugeBlack/OpenParsec starting October 2026 (GPLv3 section 5a notice):
- iPhone Duo and foldable support
- Direct touch no longer leaks a left click at the start of a two-finger gesture, or re-clicks when the screen rotates or folds under a held finger
- A connection stuck in connecting is retried once and then given up (about 90 seconds at most); an expired Parsec session signs you out cleanly
- Unit tests (`swift test`)
- Native iOS UI, light and dark themes, English and Traditional Chinese
- A new stream menu with bitrate, display switching and resolution
- Mac hosts get no resolution request and no resolution choice
- Fixes for the stretched Metal picture, keyboard hiding, a cursor data race, a clean disconnect when the app is killed, and nightly CI metadata
- A trackpad below the picture in portrait and half fold, with Mac gestures
- Renamed to Pane with a new icon and a black-and-white look

### Credit and license

Pane is made by kv and is based on [OpenParsec](https://github.com/hugeBlack/OpenParsec) by hugeBlack and its contributors, who keep the copyright to their code. Pane and kv's changes are released under the same GNU GPL v3, see [LICENSE](LICENSE). You are free to use, change and share Pane under that license; anything you distribute that is based on it has to stay under the GPL v3 as well.

Parsec and the Parsec logo are trademarks of their owner. Pane is not affiliated with or endorsed by Parsec. The Parsec SDK binary is under Parsec's own terms.

---

## 繁體中文

Pane 是 kv 開發的開源 iOS / iPadOS [Parsec](https://parsec.app) 用戶端，以 Swift、SwiftUI 與 Parsec SDK 撰寫，讓你用 iPhone、iPad 或 iPhone Duo 串流並操作你的電腦。它源自 [hugeBlack/OpenParsec](https://github.com/hugeBlack/OpenParsec) 的分支，加入摺疊機支援、原生 iOS 介面和許多修正。

### 功能

**iPhone Duo 與摺疊機**
- 展開、闔上、半摺和多視窗都支援。
- 畫面維持主機的比例，用黑邊而不是拉伸，並避開轉軸。
- 主畫面會正確填滿 Duo 的狀態列欄位。

**原生 iOS 介面**
- iOS 17 以上用側邊欄切換主機、好友和設定，只在沒有串流時出現。
- 設定是原生分組表單，登入、兩步驟驗證和連線提示也都是原生樣式。
- 黑白配色，亮色和暗色主題跟著系統切換，App icon 也有亮色、暗色和 tinted 三種版本。
- 介面有英文和繁體中文，跟著裝置語言切換，也可以在 iOS 設定裡個別指定這個 App 的語言。

**串流選單**
點浮動按鈕（iOS 26 是 Liquid Glass）會打開原生 popover，裡面有：
- **解析度**：只有主機不是 Mac 時才會出現。
- **碼率**：只套用在這次串流；「主機預設」會回到主機自己的設定。要改預設值請到設定。
- **切換螢幕**：主機有多個螢幕時才會出現。
- 聲音、固定幀率、雙指縮放、顯示連線資訊的開關。
- 隱藏按鈕和中斷連線。

也可以從螢幕邊緣滑入打開選單（設定 > 從邊緣滑出選單）。

**畫面下方的觸控板**
直向時，以及 iPhone Duo 半摺時的下半部，畫面會放在上方，下面整塊變成跟 Mac 一樣的大觸控板：

| 手勢 | 功能 |
|---|---|
| 單指 | 移動游標，快速一撥會繼續滑行 |
| 點一下 | 左鍵 |
| 按住後移動 | 拖曳（按住左鍵） |
| 雙指點一下 | 右鍵 |
| 雙指移動 | 捲動，上下或左右 |
| 雙指開合 | 縮放上方的畫面 |
| 三指點一下 | 叫出或收起鍵盤 |
| 三或四指上滑 | 指揮中心（Windows：工作檢視） |
| 三或四指下滑 | App Exposé（Windows：顯示桌面） |
| 三或四指左右滑 | 切換桌面空間（Windows：虛擬桌面） |
| 四指張開 | 顯示桌面 |
| 四指捏合 | Spotlight（Windows：開始功能表） |

**三指拖移**（設定裡，預設關閉）對應 Mac「輔助使用 > 指標控制 > 觸控式軌跡板選項 > 拖移方式」。Pane 讀不到 Mac 的設定，請兩邊設成一樣。打開後，三指移動就是按住左鍵拖曳，上面那些滑動手勢改用四指。

觸控板下方的工具列放著串流選單、指揮中心、顯示桌面和鍵盤，畫面上不會有任何按鈕。手指在玻璃上會顯示淡淡的光點，多指手勢觸發時會短暫顯示它做了什麼。

叫出鍵盤時，下方換成 iPhone 鍵盤，上面多一排 Mac 按鍵：Esc、⌃、⌥、⌘、⇧、Tab、F1 到 F12、方向鍵和 Delete，另外還有 ⌘C、⌘V、⌘X、⌘Z、⌘A（Windows 主機會送 Ctrl），以及 ⌘Tab、⌘Space、⌘H、⌘⇧3、⌘⇧4，後面這幾組用實體鍵盤按會被 iPadOS 攔走，所以放成按鈕。修飾鍵會按住，直到按下一個鍵。半摺時，系統有顯示鍵盤頂端的工具列，按鍵就會移進那裡，留在下半部；沒有的話就留在鍵盤上方。可以在「設定 > 畫面下方當觸控板」關閉。

送到主機的是手機鍵盤的語言。用地球鍵切到注音、拼音或日文假名照常打字，選字前的注音會顯示在鍵盤上方，選好字就以文字送到主機，不受 Mac 目前輸入法影響。文字是經由主機剪貼簿貼上的，主機傳過剪貼簿內容後（在主機上複製東西時就會傳），貼完會把那段文字放回去。主機 Parsec 的 `app_copy_paste` 設定要保持開啟（預設就是開）。韓文目前還不支援。

**Mac 主機**
Mac 主機會以每個螢幕本身的解析度串流，所以 Pane 會隱藏解析度選項，一律使用主機本身的尺寸。在 Mac 主機上切換到第二個螢幕的功能仍在處理中：某些環境下，主機會在幾秒後退回主螢幕。

### 系統需求

- iOS / iPadOS 15 以上。側邊欄需要 iOS 17，Liquid Glass 需要 iOS 26，摺疊機 API 需要 iOS 27。
- 一個 Parsec 帳號，以及一台在執行 Parsec 主機程式的電腦。

### 安裝

Release 裡的 `.ipa` 沒有簽章，請用以下任一種方式側載：
1. **AltStore / SideStore**：打開 App，到「My Apps」，點 +，選 `Pane.ipa`。
2. **Sideloadly**：把裝置接上電腦，把 `Pane.ipa` 拖進去，用你的 Apple ID 簽章。
3. **自己的憑證**：用你的開發者憑證重新簽章 `.ipa`。

Bundle ID 跟 OpenParsec 相同，所以 Pane 會直接覆蓋已安裝的 OpenParsec，並保留登入狀態。

### 使用方式

1. 用你的 Parsec 帳號登入。有開兩步驟驗證的帳號會跳出驗證碼輸入框。
2. 在「主機」裡選一台電腦，點「連線」。如果主機需要核准訪客，Pane 會等待核准。
3. 串流時的操作：

| 手勢 | 觸控板模式 | 直接觸控模式 |
|---|---|---|
| 單指點一下 | 左鍵 | 在點的位置按左鍵 |
| 單指拖曳 | 移動游標 | 在手指位置拖曳 |
| 長按後拖曳 | 按住左鍵（拖曳檔案、視窗） | — |
| 雙指點一下 | 右鍵 | 右鍵 |
| 雙指拖曳 | 捲動 | 捲動 |
| 雙指開合 | 縮放畫面（雙指縮放開啟時） | 同左 |
| 三指點一下 | 叫出或收起鍵盤 | 同左 |

- 螢幕鍵盤上方多一排 Mac 按鍵：Esc、⌃、⌥、⌘、⇧、Tab、F1 到 F12、方向鍵和 Delete。鍵盤擋住部分畫面時，拖曳把手就能把畫面移進來。
- **滑鼠與鍵盤**：支援 USB 和藍牙的滑鼠與鍵盤，包括 Magic Keyboard。接上實體鍵盤就能直接打字到主機，這時按鍵盤鈕只會叫出 Mac 按鍵列。接了滑鼠或觸控式軌跡板時，畫面下方的觸控板會收起，畫面改成滿版。Option 鍵可以當成 Command 鍵用（設定 > Option 鍵當 Command 鍵）。
- **遊戲手把**：串流時按任一板機鍵，Parsec 就會抓到手把。使用前要先把主機端設好，例如安裝虛擬 USB 驅動。
- **子母畫面**：離開 App 時串流會縮成浮動視窗（設定 > 子母畫面）。
- **自動重新連線**：網路斷線後會自動接回。Wi-Fi 和行動網路互切時會立刻重連；完全沒網路時（電梯、隧道）會等網路回來，再持續重試最多兩分鐘。切到別的 App 一下回來串流還在；離開比較久的話，回來時會自動重連。
- **行動網路或低數據模式**：沒自己選過位元率時，串流上限是 10 Mbps。

### 設定

| 區塊 | 可以調整的項目 |
|---|---|
| 觸控與滑鼠 | 觸控模式、哪根手指按右鍵、游標速度、游標大小、捲動速度、反向捲動、雙指縮放、畫面下方當觸控板 |
| 鍵盤 | 鍵盤按鈕、Option 鍵當 Command 鍵 |
| 影像 | 繪圖引擎（Metal 或 OpenGL）、解析度（非 Mac 主機）、碼率、幀率、固定幀率、編碼格式（H.264 或 H.265） |
| 串流時 | 串流資訊、選單按鈕、從邊緣滑出選單、隱藏狀態列、子母畫面、開始時靜音 |
| 連線 | 自動重新連線、顯示重新連線錯誤 |

### 疑難排解

**串流卡頓，或碼率一直上不了 10 Mbps**
先用 Steam Link 跑網路測試。圖上如果一直有延遲尖峰，就是 Apple Wi-Fi 的問題，App 這邊修不了（[相關討論](https://github.com/moonlight-stream/moonlight-ios/issues/627)）。把路由器頻道改到 149 會有幫助。改不了的話，把附近的 Apple 裝置（尤其是 Mac）都關機，只開要串流的裝置再測一次，沒問題了再把其他裝置開回來，通常可以維持幾小時到幾天。

**切換螢幕後又跳回主螢幕**
這是部分 Mac 主機的已知問題，正在調查中。App 會寫一份 `diagnostics.log`，可以在「檔案」App 的「我的 iPhone > Pane」裡找到，附在 issue 裡會很有幫助。

**畫面有黑邊**
這是刻意的。Pane 會維持主機的比例，不拉伸畫面，也不改主機的解析度。

### 從原始碼編譯

1. 把 Parsec SDK framework 放進 `Frameworks/`（複製或 symlink）。
2. 打開 `Pane.xcodeproj`，編譯 `Pane` scheme。
3. CI 用 Xcode 26 編譯。iOS 27 的摺疊機程式碼只有 Swift 6.4 以上的工具鏈才會編進去。

執行 `swift test` 跑單元測試（不需要模擬器）。要重新產生 App icon，執行 `swift scripts/make-icon.swift Pane/Assets.xcassets`。介面字串在 `Pane/Localizable.xcstrings`。

### 與 OpenParsec 的差異

2026 年 10 月起由 hugeBlack/OpenParsec 修改而來（GPLv3 第 5a 條修改聲明）：
- iPhone Duo 與摺疊機支援
- 直接觸控在雙指手勢開頭不會多點一下左鍵，手指按著時旋轉或摺疊也不會再點一次
- 卡在「連線中」會重試一次後放棄（最長約 90 秒）；Parsec 登入過期會乾淨地登出
- 單元測試（`swift test`）
- 原生 iOS 介面、亮暗主題、英文與繁體中文
- 新的串流選單，含碼率、切換螢幕與解析度
- Mac 主機不送解析度、隱藏解析度選項
- 修正 Metal 畫面拉伸、收鍵盤、游標資料競態、App 被關掉時正確斷線，以及 nightly CI 的版本資訊
- 直向與半摺時畫面下方的 Mac 手勢觸控板
- 改名為 Pane，換上新的 icon 與黑白配色

### 致謝與授權

Pane 由 kv 開發，基於 hugeBlack 與其他貢獻者的 [OpenParsec](https://github.com/hugeBlack/OpenParsec)，原始程式碼的著作權仍屬於他們。Pane 與 kv 的修改同樣以 GNU GPL v3 授權釋出，見 [LICENSE](LICENSE)。你可以依這份授權自由使用、修改與散布 Pane；若散布以它為基礎的作品，也必須同樣以 GPL v3 授權。

Parsec 名稱與標誌是其所有者的商標，Pane 與 Parsec 官方沒有關聯，也未經其背書。Parsec SDK 二進位檔適用 Parsec 自己的條款。
