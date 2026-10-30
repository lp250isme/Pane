import UIKit

protocol TrackpadDelegate: AnyObject {
	/// a finger landed: stop any glide so a tap lands where the cursor is now
	func trackpadTouchBegan()
	/// the pad is moving the cursor itself (pointer or drag), so the host's late reports must not pull it back
	func trackpadCursorActive(_ active: Bool)
	/// one finger moving, in screen points
	func trackpadMove(by delta: CGPoint)
	/// the moving finger lifted, so a flick can glide on
	func trackpadMoveEnded()
	func trackpadButton(_ button: Int32, pressed: Bool)
	func trackpadTap(_ tap: TrackpadTap)
	/// two fingers moving together, in screen points
	func trackpadScroll(by delta: CGPoint)
	func trackpadScrollEnded()
	func trackpadZoom(by scale: CGFloat)
	func trackpadGesture(_ gesture: TrackpadGesture)
}

/// The space below the picture (portrait, or the lower half of a half fold) as a Mac-style trackpad.
/// One finger moves the cursor, a tap clicks, press and hold then move drags, two fingers scroll or
/// pinch, three or four fingers swipe for Mission Control and Spaces, four fingers pinch or spread.
/// It owns its touches: the stream's overlay and tap recognizers leave them alone.
final class TrackpadView: UIView {
	weak var delegate: TrackpadDelegate?

	private enum Mode { case idle, pointer, drag, scroll, zoom, multi }
	private var mode = Mode.idle
	private var fingers: [UITouch] = []
	private var maxFingers = 0
	private var startTime: TimeInterval = 0
	private var moved = false
	private var startCentroid = CGPoint.zero
	private var lastCentroid = CGPoint.zero
	private var startSpread: CGFloat = 0
	private var lastSpread: CGFloat = 0
	private var gestureSent = false
	private var holdTimer: DispatchWorkItem?
	private var ignoreUntilLift = false

	private let tapSlop: CGFloat = 10
	private let tapTime: TimeInterval = 0.3
	private let holdTime: TimeInterval = 0.5
	private let swipeDistance: CGFloat = 60
	private let feedback = UIImpactFeedbackGenerator(style: .light)

	// the pad sits on the stream's black in either theme, so it is drawn light-on-dark
	private let surface: UIView
	private let rim = CALayer()
	private let dotLayer = UIView()
	private var dots: [UITouch: UIView] = [:]
	private let hint = UILabel()
	private let hud = UIView()
	private let hudIcon = UIImageView()
	private let hudLabel = UILabel()
	private var hudHide: DispatchWorkItem?
	private var hintDismissed = false
	private static let corner: CGFloat = 28

	override init(frame: CGRect) {
		// Liquid Glass frames the pad on iOS 26 (it reads as a dark pane on the black stream); a faint
		// fill before that, and whenever Reduce Transparency is on
		if #available(iOS 26, *), !UIAccessibility.isReduceTransparencyEnabled {
			let glass = UIVisualEffectView(effect: UIGlassEffect())
			// glass takes its shape from the corner configuration, not the layer (it defaults to a capsule)
			glass.cornerConfiguration = .corners(radius: .fixed(Self.corner))
			surface = glass
		} else {
			surface = UIView()
			surface.backgroundColor = UIColor(white: 1, alpha: 0.08)
		}
		super.init(frame: frame)
		isMultipleTouchEnabled = true
		backgroundColor = .clear
		// the pad always sits on the stream's black, so its glass and text stay in their dark form
		overrideUserInterfaceStyle = .dark

		surface.isUserInteractionEnabled = false
		surface.layer.cornerRadius = Self.corner
		surface.layer.cornerCurve = .continuous
		surface.clipsToBounds = true
		addSubview(surface)

		// a hairline that brightens while a drag holds the button down
		rim.cornerRadius = Self.corner
		rim.cornerCurve = .continuous
		rim.borderWidth = 1
		rim.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
		layer.addSublayer(rim)

		hint.numberOfLines = 0
		hint.textAlignment = .center
		hint.font = .preferredFont(forTextStyle: .footnote)
		hint.adjustsFontForContentSizeCategory = true
		hint.textColor = UIColor(white: 1, alpha: 0.42)
		hint.text = String(localized: "One finger to move, tap to click\nTwo fingers to scroll or right click\nThree or four fingers to swipe between desktops")
		hint.isUserInteractionEnabled = false
		addSubview(hint)

		dotLayer.isUserInteractionEnabled = false
		addSubview(dotLayer)

		hud.isUserInteractionEnabled = false
		hud.backgroundColor = UIColor(white: 0.12, alpha: 0.92)
		hud.layer.cornerCurve = .continuous
		hud.layer.borderWidth = 1
		hud.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
		hud.alpha = 0
		hudIcon.tintColor = .white
		hudIcon.contentMode = .scaleAspectFit
		hudIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
		hudLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
		hudLabel.textColor = .white
		hud.addSubview(hudIcon)
		hud.addSubview(hudLabel)
		addSubview(hud)

		isAccessibilityElement = true
		accessibilityLabel = String(localized: "Trackpad")
		accessibilityHint = hint.text
	}

	/// a short label for the multi-finger gesture that just went to the host
	func showHUD(title: String, symbol: String) {
		hudIcon.image = UIImage(systemName: symbol)
		hudLabel.text = title
		hudLabel.sizeToFit()
		let h: CGFloat = 36, iconW: CGFloat = 20
		let w = 14 + iconW + 8 + hudLabel.bounds.width + 16
		hud.bounds = CGRect(x: 0, y: 0, width: w, height: h)
		hud.layer.cornerRadius = h / 2
		hudIcon.frame = CGRect(x: 14, y: (h - iconW) / 2, width: iconW, height: iconW)
		hudLabel.frame = CGRect(x: 14 + iconW + 8, y: (h - hudLabel.bounds.height) / 2, width: hudLabel.bounds.width, height: hudLabel.bounds.height)
		hud.center = CGPoint(x: bounds.midX, y: surface.frame.minY + 14 + h / 2)
		hudHide?.cancel()
		hud.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
		UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
			self.hud.alpha = 1
			self.hud.transform = .identity
		}
		let hide = DispatchWorkItem { [weak self] in
			UIView.animate(withDuration: 0.3) { self?.hud.alpha = 0 }
		}
		hudHide = hide
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: hide)
	}

	private func setDragging(_ dragging: Bool) {
		CATransaction.begin()
		CATransaction.setAnimationDuration(0.2)
		rim.borderColor = UIColor(white: 1, alpha: dragging ? 0.55 : 0.14).cgColor
		rim.borderWidth = dragging ? 2 : 1
		CATransaction.commit()
	}

	// a soft light under each finger, so the pad shows what it is reading
	private func updateDots(_ live: [UITouch]) {
		for (touch, dot) in dots where !live.contains(touch) {
			dots[touch] = nil
			UIView.animate(withDuration: 0.25, animations: {
				dot.alpha = 0
				dot.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
			}, completion: { _ in dot.removeFromSuperview() })
		}
		for touch in live {
			let point = touch.location(in: self)
			if let dot = dots[touch] {
				dot.center = point
				continue
			}
			let d: CGFloat = 44
			let dot = UIView(frame: CGRect(x: 0, y: 0, width: d, height: d))
			dot.layer.cornerRadius = d / 2
			dot.backgroundColor = UIColor(white: 1, alpha: 0.18)
			dot.layer.borderWidth = 1
			dot.layer.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
			dot.center = point
			dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
			dot.alpha = 0
			dotLayer.addSubview(dot)
			dots[touch] = dot
			UIView.animate(withDuration: 0.18) {
				dot.alpha = 1
				dot.transform = .identity
			}
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let pad = bounds.insetBy(dx: 12, dy: 8)
		surface.frame = pad
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		rim.frame = pad
		CATransaction.commit()
		dotLayer.frame = bounds
		let hintSize = hint.sizeThatFits(CGSize(width: pad.width - 40, height: pad.height))
		hint.frame = CGRect(x: pad.midX - hintSize.width / 2, y: pad.midY - hintSize.height / 2, width: hintSize.width, height: hintSize.height)
		// recomputed every pass, so an early tiny layout doesn't hide it for good
		hint.isHidden = hintDismissed || bounds.width < 1 || pad.height < hintSize.height + 24
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(event, cancelled: true) }

	/// drop everything, letting go of a held button (rotate, fold, backgrounding)
	func reset() {
		holdTimer?.cancel()
		holdTimer = nil
		if mode == .drag { delegate?.trackpadButton(1, pressed: false) }
		delegate?.trackpadCursorActive(false)
		// fingers still down would otherwise start a fresh gesture (and a hold-to-drag) where they are
		ignoreUntilLift = !fingers.isEmpty
		setDragging(false)
		updateDots([])
		mode = .idle
		fingers = []
		maxFingers = 0
	}

	private func update(_ event: UIEvent?, cancelled: Bool = false) {
		let live = (event?.touches(for: self) ?? [])
			.filter { $0.phase != .ended && $0.phase != .cancelled }
			.sorted { $0.timestamp < $1.timestamp }
		updateDots(live)
		// the hint is for the first look; once a finger lands it has done its job
		if !live.isEmpty && !hintDismissed {
			hintDismissed = true
			UIView.animate(withDuration: 0.3, animations: { self.hint.alpha = 0 }, completion: { _ in self.hint.isHidden = true })
		}
		if ignoreUntilLift {
			if live.isEmpty { ignoreUntilLift = false }
			return
		}
		if live.isEmpty {
			if !fingers.isEmpty { finish(cancelled: cancelled) }
			return
		}
		if fingers.isEmpty {
			begin(live)
		} else if live.count > fingers.count {
			addFingers(live)
		} else if live.count < fingers.count {
			// fingers rarely lift in the same frame: measure from the ones left, or the jump in their
			// centre reads as movement and a two or three finger tap is lost
			fingers = live
			if mode == .drag {
				lastCentroid = centroid()
				lastSpread = spread()
			} else {
				measureFromHere()
			}
			return
		} else {
			fingers = live
		}
		track()
	}

	private func begin(_ live: [UITouch]) {
		fingers = live
		maxFingers = live.count
		mode = .idle
		moved = false
		gestureSent = false
		startTime = CACurrentMediaTime()
		measureFromHere()
		feedback.prepare()
		delegate?.trackpadTouchBegan()
		if live.count == 1 { scheduleHold() }
	}

	private func addFingers(_ live: [UITouch]) {
		fingers = live
		maxFingers = max(maxFingers, live.count)
		holdTimer?.cancel()
		// a drag keeps its button and just re-bases so the cursor doesn't jump; anything else starts
		// measuring the bigger gesture afresh
		if mode == .drag {
			lastCentroid = centroid()
			lastSpread = spread()
		} else {
			if mode == .pointer { delegate?.trackpadCursorActive(false) }
			mode = .idle
			measureFromHere()
		}
	}

	private func measureFromHere() {
		startCentroid = centroid()
		lastCentroid = startCentroid
		startSpread = spread()
		lastSpread = startSpread
	}

	// press and hold without moving: the left button goes down and the finger drags
	private func scheduleHold() {
		holdTimer?.cancel()
		let timer = DispatchWorkItem { [weak self] in
			guard let self, self.fingers.count == 1, self.maxFingers == 1, !self.moved, self.mode == .idle else { return }
			self.mode = .drag
			self.setDragging(true)
			self.delegate?.trackpadCursorActive(true)
			self.feedback.impactOccurred()
			self.delegate?.trackpadButton(1, pressed: true)
		}
		holdTimer = timer
		DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: timer)
	}

	private func track() {
		let c = centroid()
		let s = spread()
		if !moved && (hypot(c.x - startCentroid.x, c.y - startCentroid.y) > tapSlop || abs(s - startSpread) > tapSlop) {
			moved = true
			if mode != .drag { holdTimer?.cancel() }
		}
		let delta = CGPoint(x: c.x - lastCentroid.x, y: c.y - lastCentroid.y)

		switch fingers.count {
		case 1:
			// the finger left over from a two or more finger gesture stays inert until all lift
			if mode == .drag || mode == .pointer {
				delegate?.trackpadMove(by: delta)
			} else if maxFingers == 1 && moved {
				// the first move carries what the finger travelled inside the tap slop too
				mode = .pointer
				delegate?.trackpadCursorActive(true)
				delegate?.trackpadMove(by: CGPoint(x: c.x - startCentroid.x, y: c.y - startCentroid.y))
			}
		case 2 where mode != .drag:
			if mode == .idle || mode == .pointer, moved {
				let spreadChange = abs(s - startSpread)
				let travel = hypot(c.x - startCentroid.x, c.y - startCentroid.y)
				mode = spreadChange > travel ? .zoom : .scroll
			}
			if mode == .scroll {
				delegate?.trackpadScroll(by: delta)
			} else if mode == .zoom, lastSpread > 0, s > 0 {
				delegate?.trackpadZoom(by: s / lastSpread)
			}
		case 2:
			delegate?.trackpadMove(by: delta)
		default:
			// extra fingers during a drag keep dragging; turning it into a swipe would never let go of the button
			if mode == .drag {
				delegate?.trackpadMove(by: delta)
				break
			}
			mode = .multi
			guard !gestureSent else { break }
			let travel = CGVector(dx: c.x - startCentroid.x, dy: c.y - startCentroid.y)
			let gesture = trackpadSwipe(travel, threshold: swipeDistance)
				?? (fingers.count >= 4 && startSpread > 0 ? trackpadPinch(spreadRatio: s / startSpread) : nil)
			if let gesture {
				gestureSent = true
				feedback.impactOccurred()
				delegate?.trackpadGesture(gesture)
			}
		}
		lastCentroid = c
		lastSpread = s
	}

	private func finish(cancelled: Bool) {
		holdTimer?.cancel()
		holdTimer = nil
		delegate?.trackpadCursorActive(false)
		switch mode {
		case .drag:
			setDragging(false)
			delegate?.trackpadButton(1, pressed: false)
		case .pointer:
			delegate?.trackpadMoveEnded()
		case .scroll:
			delegate?.trackpadScrollEnded()
		default:
			if !cancelled, !moved, CACurrentMediaTime() - startTime < tapTime, let tap = trackpadTap(fingers: maxFingers) {
				delegate?.trackpadTap(tap)
			}
		}
		mode = .idle
		fingers = []
		maxFingers = 0
	}

	private func centroid() -> CGPoint {
		guard !fingers.isEmpty else { return .zero }
		let points = fingers.map { $0.location(in: self) }
		return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
					   y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
	}

	// average distance from the centroid: how far apart the fingers are
	private func spread() -> CGFloat {
		guard fingers.count >= 2 else { return 0 }
		let c = centroid()
		return fingers.map { hypot($0.location(in: self).x - c.x, $0.location(in: self).y - c.y) }.reduce(0, +) / CGFloat(fingers.count)
	}
}

private extension UIFont {
	func withWeight(_ weight: UIFont.Weight) -> UIFont {
		UIFont.systemFont(ofSize: pointSize, weight: weight)
	}
}
