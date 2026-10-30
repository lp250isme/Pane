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
