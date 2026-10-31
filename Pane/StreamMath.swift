import CoreGraphics

// Pure stream logic, no UIKit or Parsec SDK, so `swift test` can cover it on a Mac.

/// The hostOS a Mac host reports (parsecd answers getVideoConfig with a constant 2)
let macHostOS = 2

/// The stream size to ask the host for. A Mac host streams each display at its own size
/// (parsecd has no display-mode API), so it gets its default 0x0 rather than a size it can't honour.
func requestedResolution(hostOS: Int?, picked: (x: Int, y: Int)) -> (x: Int, y: Int) {
	hostOS == macHostOS ? (0, 0) : picked
}

/// Keeps the cursor on the same spot of the picture when the view resizes (rotate, fold). The picture is
/// letterboxed into the view, so the point goes through host coordinates rather than scaling with the view.
func carryCursor(_ point: CGPoint, from old: CGSize, to new: CGSize, host: CGSize) -> CGPoint {
	guard host.width > 0, host.height > 0 else {
		return CGPoint(x: point.x * new.width / old.width, y: point.y * new.height / old.height)
	}
	let oldScale = min(old.width / host.width, old.height / host.height)
	let newScale = min(new.width / host.width, new.height / host.height)
	let hostX = (point.x - (old.width - host.width * oldScale) / 2) / oldScale
	let hostY = (point.y - (old.height - host.height * oldScale) / 2) / oldScale
	let x = hostX * newScale + (new.width - host.width * newScale) / 2
	let y = hostY * newScale + (new.height - host.height * newScale) / 2
	return CGPoint(x: min(max(x, 0), new.width), y: min(max(y, 0), new.height))
}

/// Direct touch's left button. The press is held back a beat after the first finger lands, so a second
/// finger in that time turns the touch into a two-finger gesture (right click, scroll, zoom) instead of
/// leaking a left click to the host.
struct DirectClick {
	private(set) var pending = false
	private(set) var down = false

	/// first finger landed: a press is owed but not sent yet
	mutating func begin() {
		pending = true
		down = false
	}

	/// the wait ran out or the finger really started dragging: true when the press must go out now
	mutating func press() -> Bool {
		guard pending else { return false }
		pending = false
		down = true
		return true
	}

	/// a second finger landed: the held-back press never happens
	mutating func cancel() {
		pending = false
	}

	/// finger lifted: a quick tap still owes its press, then the release
	mutating func lift() -> (press: Bool, release: Bool) {
		let pressed = press()
		let release = down
		down = false
		return (pressed, release)
	}
}

// MARK: - Trackpad below the picture (portrait, or the lower half of a half fold)

/// USB HID codes, which is what ParsecKeycode uses
enum HIDKey {
	static let d: UInt32 = 7, h: UInt32 = 11, three: UInt32 = 32, four: UInt32 = 33, tab: UInt32 = 43, space: UInt32 = 44, f11: UInt32 = 68
	static let right: UInt32 = 79, left: UInt32 = 80, down: UInt32 = 81, up: UInt32 = 82
	static let ctrl: UInt32 = 224, shift: UInt32 = 225, alt: UInt32 = 226, gui: UInt32 = 227
	static let a: UInt32 = 4, c: UInt32 = 6, v: UInt32 = 25, x: UInt32 = 27, z: UInt32 = 29
	// stands for ⌘ on a Mac host and Ctrl elsewhere, resolved by hostKeys
	static let primary: UInt32 = 0xFFFF
}

/// A combo as the host should get it: copy and paste are ⌘ on a Mac, Ctrl on Windows
func hostKeys(_ combo: [UInt32], hostOS: Int?) -> [UInt32] {
	combo.map { $0 == HIDKey.primary ? (hostOS == macHostOS ? HIDKey.gui : HIDKey.ctrl) : $0 }
}

/// Keyboards that compose in marked text (注音, pinyin, kana) and so need a real text field to type into.
/// ponytail: Korean left out, its keyboard rewrites the last syllable rather than marking it
func needsComposer(language: String?) -> Bool {
	guard let language else { return false }
	return ["zh", "ja", "yue"].contains { language.hasPrefix($0) }
}

/// Sent as one key when the host's keys can type it, otherwise as text through the host's clipboard
func typesAsKey(_ text: String) -> Bool { text.count == 1 && text.allSatisfy(\.isASCII) }

/// The SDK's mod-field bit for a modifier's HID code (left and right ctrl, shift, alt, gui), nil for other keys
func modifierBit(hidCode: UInt32) -> UInt32? {
	switch hidCode {
	case 224: return 0x0040
	case 225: return 0x0001
	case 226: return 0x0100
	case 227: return 0x0400
	case 228: return 0x0080
	case 229: return 0x0002
	case 230: return 0x0200
	case 231: return 0x0800
	default: return nil
	}
}

enum TrackpadGesture: Equatable {
	case swipeUp, swipeDown, swipeLeft, swipeRight, spread, pinch
}

/// What a quick tap does, by the most fingers that were down
enum TrackpadTap: Equatable {
	case leftClick, rightClick, toggleKeyboard
}

func trackpadTap(fingers: Int) -> TrackpadTap? {
	switch fingers {
	case 1: return .leftClick
	case 2: return .rightClick
	case 3: return .toggleKeyboard
	default: return nil
	}
}

/// The direction of a multi-finger swipe once it has travelled far enough, nil before that
func trackpadSwipe(_ translation: CGVector, threshold: CGFloat) -> TrackpadGesture? {
	let dx = translation.dx, dy = translation.dy
	guard max(abs(dx), abs(dy)) >= threshold else { return nil }
	if abs(dx) > abs(dy) { return dx < 0 ? .swipeLeft : .swipeRight }
	return dy < 0 ? .swipeUp : .swipeDown
}

/// How many fingers swipe between desktops: three-finger drag takes three, so swipes move to four, as on a Mac
func trackpadSwipeFingers(threeFingerDrag: Bool) -> Int { threeFingerDrag ? 4 : 3 }

/// Four fingers closing or opening, judged by how far apart they ended up against how they started
func trackpadPinch(spreadRatio: CGFloat) -> TrackpadGesture? {
	if spreadRatio < 0.65 { return .pinch }
	if spreadRatio > 1.5 { return .spread }
	return nil
}

/// The key combo a multi-finger gesture sends, matched to what the host's own trackpad does.
/// Mac: up Mission Control, down App Exposé, left / right the next / previous Space, spread Show Desktop,
/// pinch Spotlight (Launchpad has no key). Windows: Task View, show desktop, virtual desktops, Start.
func trackpadKeys(_ gesture: TrackpadGesture, hostOS: Int?) -> [UInt32] {
	if hostOS == macHostOS {
		switch gesture {
		case .swipeUp: return [HIDKey.ctrl, HIDKey.up]
		case .swipeDown: return [HIDKey.ctrl, HIDKey.down]
		// content follows the fingers: swiping left brings in the Space on the right
		case .swipeLeft: return [HIDKey.ctrl, HIDKey.right]
		case .swipeRight: return [HIDKey.ctrl, HIDKey.left]
		case .spread: return [HIDKey.f11]
		case .pinch: return [HIDKey.gui, HIDKey.space]
		}
	}
	switch gesture {
	case .swipeUp: return [HIDKey.gui, HIDKey.tab]
	case .swipeDown, .spread: return [HIDKey.gui, HIDKey.d]
	case .swipeLeft: return [HIDKey.ctrl, HIDKey.gui, HIDKey.right]
	case .swipeRight: return [HIDKey.ctrl, HIDKey.gui, HIDKey.left]
	case .pinch: return [HIDKey.gui]
	}
}

/// Where the picture sits when the trackpad shares the screen: top-aligned at the host's aspect, so the
/// space below is left for the trackpad. Nil when there's no room worth a trackpad (landscape, a host that
/// matches the screen's shape) and the picture keeps the whole view.
func pictureAboveTrackpad(in bounds: CGRect, topInset: CGFloat, host: CGSize, minTrackpad: CGFloat) -> CGRect? {
	guard host.width > 0, host.height > 0, bounds.height > bounds.width else { return nil }
	let height = (bounds.width * host.height / host.width).rounded()
	guard bounds.height - topInset - height >= minTrackpad else { return nil }
	return CGRect(x: bounds.minX, y: bounds.minY + topInset, width: bounds.width, height: height)
}

/// A float as the Int32 the SDK takes. Int32(_:) traps on NaN, infinity or out of range, which a bad size
/// (a host reporting 0x0 mid-change) or a runaway glide can produce
func hostInt<F: BinaryFloatingPoint>(_ v: F) -> Int32 {
	guard v.isFinite else { return 0 }
	if v >= F(Int32.max) { return .max }
	if v <= F(Int32.min) { return .min }
	return Int32(v)
}

/// Seconds to wait before reconnect try `attempt` (0 = the first): soon at first, then backing off
func reconnectGap(attempt: Int) -> Double {
	[0, 2, 5, 10, 15][min(max(attempt, 0), 4)] + (attempt > 4 ? 5 : 0)
}

/// How long a lost stream keeps retrying once there is a network, before giving up
let reconnectBudget: Double = 120

/// The bitrate asked of the host on cellular or Low Data Mode when none was picked: the host's default, at most 10 Mbps
func meteredBitrate(hostDefault: Int) -> Int { hostDefault > 0 ? min(hostDefault, 10) : 10 }
