import Foundation
import UIKit
import ParsecSDK
import QuartzCore
import GameController
import os

protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	var renderView: UIView { get }
	func viewDidLoad()
	func cleanUp()
	func updateSize(width: CGFloat, height: CGFloat)
}

class ParsecViewController: UIViewController, UIScrollViewDelegate, ParsecTouchInputDelegate {
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u: UIImageView?
	var lastImg: CGImage?
    var lastMouseX: Int32 = -1
    var lastMouseY: Int32 = -1
    var lastCursorHidden: Bool = false
	var zoomEnabled = false
	var appliedRenderScale: CGFloat = 0       // last contentScaleFactor applied (avoids redundant reallocations)
	let maxRenderScale: CGFloat = 6.0         // cap on drawable density
	var clickHoldActive = false        // left button held via long-press (file drag)
	// Flick-to-glide momentum (tuned constants, not user settings).
	var momentumLink: CADisplayLink?
	var cursorMomentumActive = false
	var scrollMomentumActive = false
	var edgeScrollActive = false
	var edgeScrollPoint: CGPoint = .zero
	var edgeScrollLastTick: CFTimeInterval = 0
	let edgeScrollMargin: CGFloat = 44.0
	let edgeScrollMaxSpeed: CGFloat = 900.0
	var cursorVelocity: CGPoint = .zero     // content points / sec
	var scrollVelocity: Float = 0.0         // wheel units / sec
	var lastCursorMoveTime: CFTimeInterval = 0
	var lastScrollMoveTime: CFTimeInterval = 0
	let flingMinSpeed: CGFloat = 80.0       // min release speed (content pts/sec) to start a cursor glide
	let cursorStopSpeed: CGFloat = 40.0     // end the glide below this speed (lower = gentler, less abrupt)
	let cursorDecayPerSec: Double = 0.08    // fraction of speed left after 1s (bigger = longer glide)
	let scrollStartSpeed: Float = 800.0     // min release speed (wheel units/sec) to start a scroll glide
	let scrollStopSpeed: Float = 200.0
	let scrollDecayPerSec: Double = 0.004
	// A left click fires only if the finger barely moved (else it's a cursor nudge).
	var cursorDidMoveThisTouch = false
	var singleTouchStartScreen: CGPoint = .zero
	let tapMoveSlop: CGFloat = 4.0          // finger movement (pts) above which a touch is a drag, not a tap
	let staleTouchThreshold: TimeInterval = 1.5   // a touch idle this long vs an actively-moving one is a ghost
	let staleMoveSlop: CGFloat = 24.0        // the moving finger must travel this far before a ghost is swept
	var twoFingerDidMove = false            // true once a 2-finger gesture became a pinch/scroll (suppresses right-click)

	var mouseSensitivity: Float = Float(SettingsHandler.mouseSensitivity)
	// Two-finger scroll-wheel accumulation, kept separate from cursor movement.
	var lastScrollTranslation: CGPoint = .zero
	var accumulatedScrollY: Float = 0.0
	var accumulatedScrollX: Float = 0.0
	var scrollWheelSpeed: Float { Float(SettingsHandler.scrollSensitivity) * 2.3 }

	// Input-driven cursor + viewport state (manual touch handling via TouchOverlayView).
	var touchOverlay: TouchOverlayView!
	var cursorContentPos: CGPoint = .zero
	var isDragging = false
	var twoFingerResidual = false       // leftover finger after a 2-finger gesture; inert until full lift
	var waitForLift = false             // touches were flushed (rotate, fold) with fingers down; ignore them until all lift
	var waitForLiftSince: CFTimeInterval = 0
	var directClick = DirectClick()     // direct mode's left button, held back a beat in case a second finger lands
	var directPressTimer: DispatchWorkItem?
	var activeTouches: [UITouch] = []   // ordered; first two drive pinch / scroll
	var touchOrigins: [UITouch: CGPoint] = [:]   // begin location per touch, for ghost-sweep movement test

	enum TwoFingerMode { case undecided, zoom, scroll }
	var twoFingerMode: TwoFingerMode = .undecided
	var startPinchDistance: CGFloat = 0
	var lastPinchDistance: CGFloat = 0
	var startTwoFingerMidpoint: CGPoint = .zero
	var lastTwoFingerMidpoint: CGPoint = .zero

	var keyboardAccessoriesView: UIView?
	var keyboardHeight: CGFloat = 0.0
	var keyboardVisible: Bool = false
	var pinnedToKeyboard = false
	var onKeyboardCoversPicture: (() -> Void)?
	private var panHandle: UIImageView?
	private var keyScrollView: UIScrollView?
	private var keyBarDone: UIButton?
	// the Mac keys ride in the keyboard's shortcut bar when half open; nil until a keyboard shows whether there is one
	private var keysInShortcutBar = false
	private var shortcutBarKeys: [KeyboardButton] = []
	private var shortcutBarShown: Bool?
	private var panStartOffset: CGPoint = .zero
	private var keyboardCoversPicture = false
	var onKeyboardVisibilityChanged: ((Bool) -> Void)?
	var onMenuEdgeSwipe: (() -> Void)?
	var menuEdgeSwipe: UIScreenEdgePanGestureRecognizer?
	var menuEdgeSwipeRight: UIScreenEdgePanGestureRecognizer?
	var scrollView: UIScrollView!
	var contentView: UIView!
	var lastLaidOutFrame: CGRect = .zero
	var trackpad: TrackpadView!
	// the deck's toolbar (menu, Mission Control, desktop, keyboard) is SwiftUI; it learns where to sit from this
	var onDeckToolbarChanged: ((CGRect?) -> Void)?
	private var lastDeckToolbar: CGRect?
	var deckToolbarFrame: CGRect? { lastDeckToolbar }
	static let deckToolbarHeight: CGFloat = 64
	var trackpadOwnsCursor = false       // a finger is moving the cursor on the trackpad; the host's late reports must not pull it back
	private var lastHostSize: CGSize = .zero

	// the window's own screen: a foldable moves the scene between the outer and inner panel
	var screenScale: CGFloat {
		let s = traitCollection.displayScale
		return s > 0 ? s : UIScreen.main.scale   // 0 until the view is in a window
	}

	override var prefersPointerLocked: Bool {
		return true
	}

	override var prefersHomeIndicatorAutoHidden: Bool {
		return true
	}

	init() {
		super.init(nibName: nil, bundle: nil)

		let update: () -> Void = { [weak self] in self?.updateImage() }
		let metal = SettingsHandler.renderer == .metal ? ParsecMetalViewController(viewController: self, updateImage: update) : nil
		if let metal = metal, metal.metalRenderer != nil {
			self.glkView = metal
			CParsec.runningRenderer = .metal
			appNote("[renderer] metal")
		} else {
			CParsec.runningRenderer = .opengl
			appNote("[renderer] opengl")
			if metal != nil {
				os_log("%{public}@", log: sdkLog, type: .error, "metal could not start, using opengl")
			}
			self.glkView = ParsecGLKViewController(viewController: self, updateImage: update)
		}

		self.gamePadController = GamepadController()
		self.touchController = TouchController()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func computeRenderScale() -> CGFloat {
		let nativeScale = view.window?.windowScene?.screen.nativeScale ?? screenScale
		guard scrollView.zoomScale > 1.01 else { return nativeScale }
		let vw = glkView.renderView.frame.size.width
		let vh = glkView.renderView.frame.size.height
		let sw = CGFloat(CParsec.hostWidth)
		let sh = CGFloat(CParsec.hostHeight)
		guard vw > 0, vh > 0, sw > 0, sh > 0 else { return nativeScale }
		// Match the drawable to the source so zoom stays crisp without rendering wasted pixels.
		let needed = max(sw / vw, sh / vh)
		return min(maxRenderScale, max(nativeScale, needed))
	}

	func updateRenderScale() {
		let target = computeRenderScale()
		if abs(target - appliedRenderScale) > 0.01 {
			appliedRenderScale = target
			DispatchQueue.main.async { [weak self] in
				self?.glkView.renderView.contentScaleFactor = target
			}
		}
	}

	func updateImage() {
		updateRenderScale()
		// a new host size (display switch) moves the line between picture and trackpad
		let host = CGSize(width: CGFloat(CParsec.hostWidth), height: CGFloat(CParsec.hostHeight))
		if host != lastHostSize {
			lastHostSize = host
			view.setNeedsLayout()
		}
        // Optimization: Snap current valus
        let currentMouseX = CParsec.mouseInfo.mouseX
        let currentMouseY = CParsec.mouseInfo.mouseY
        let currentHidden = CParsec.mouseInfo.cursorHidden
        let currentImg = CParsec.mouseInfo.cursorImg

        // Skip if nothing changed
        if currentMouseX == lastMouseX &&
           currentMouseY == lastMouseY &&
           currentHidden == lastCursorHidden &&
           currentImg == lastImg {
            return
        }

        lastMouseX = currentMouseX
        lastMouseY = currentMouseY
        lastCursorHidden = currentHidden

		if currentImg != nil && !currentHidden {
			u?.isHidden = false
			if lastImg != currentImg {
				u!.image = UIImage(cgImage: currentImg!)
				lastImg = currentImg!
			}

			// While dragging, the touch handler owns the cursor position and viewport (smooth,
			// input-driven). When idle, follow the host's reported cursor so host- or keyboard-
			// driven moves are reflected and any prediction drift is corrected.
			if !isDragging && !clickHoldActive && !cursorMomentumActive && !trackpadOwnsCursor {
				let fingerSet = SettingsHandler.cursorMode == .direct
					&& abs(cursorContentPos.x - CGFloat(currentMouseX)) < 1
					&& abs(cursorContentPos.y - CGFloat(currentMouseY)) < 1
				cursorContentPos = CGPoint(x: CGFloat(currentMouseX), y: CGFloat(currentMouseY))
				positionCursorOverlay()
				if scrollView.zoomScale > 1.0 {
					if !fingerSet {
						centerViewportOnCursorPos()
						positionCursorOverlay()
					}
				} else {
					// Not zoomed: keep the cursor above the on-screen keyboard.
					keepCursorAboveKeyboard()
				}
			}
		} else {
			u?.isHidden = true
		}
	}

	override func viewDidLoad() {
		// ScrollView Setup
		scrollView = UIScrollView(frame: view.bounds)
		scrollView.delegate = self
		scrollView.minimumZoomScale = 1.0
		scrollView.maximumZoomScale = 5.0
		scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		// The scroll view is a programmatically-driven zoom/pan container only. Every touch is
		// owned by touchOverlay (created below); the scroll view's own gestures are disabled so
		// they can never race with or swallow our cursor / pinch / scroll handling.
		scrollView.panGestureRecognizer.isEnabled = false
		scrollView.pinchGestureRecognizer?.isEnabled = false
		scrollView.isScrollEnabled = false
		scrollView.bouncesZoom = false
		view.addSubview(scrollView)

        // ContentView
		contentView = UIView(frame: view.bounds)
		scrollView.addSubview(contentView)
		scrollView.contentSize = view.bounds.size

        // Initialize GLKView
		glkView.viewDidLoad()

		// Move GLKView to ContentView
		// glkView.viewDidLoad() adds the view to 'view', we need to move it.
		glkView.renderView.removeFromSuperview()
		contentView.addSubview(glkView.renderView)

		if #available(iOS 15.0, *) {
			if SettingsHandler.enablePiP {
				if let parsecGLK = glkView as? ParsecGLKViewController, let eaglContext = parsecGLK.eaglContext {
					PictureInPictureManager.shared.setup(sourceView: view, glContext: eaglContext)
				} else if glkView is ParsecMetalViewController {
					PictureInPictureManager.shared.setup(sourceView: view, glContext: nil)
				}
			}
		}

		touchController.viewDidLoad()
		gamePadController.viewDidLoad()

		// Touch overlay: a transparent sibling ON TOP of the scroll view (and above the gamepad /
		// touch controllers) that captures every raw touch and routes it deterministically
		// (1 finger = cursor, 2 fingers = pinch / scroll). Added before the cursor image and the
		// keyboard toolbar so those stay on top of it.
		touchOverlay = TouchOverlayView(frame: view.bounds)
		touchOverlay.backgroundColor = .clear
		touchOverlay.isMultipleTouchEnabled = true
		touchOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		touchOverlay.inputDelegate = self
		view.addSubview(touchOverlay)

		// below the picture in portrait or a half fold; above the overlay so it gets its own touches
		trackpad = TrackpadView(frame: .zero)
		trackpad.delegate = self
		trackpad.isHidden = true
		view.addSubview(trackpad)

		// Cursor is a screen-space overlay ON TOP of everything (not inside the scroll view), so the
		// zoom transform never scales it - keeping it crisp and a constant on-screen size.
		u = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
		u!.isUserInteractionEnabled = false
		view.addSubview(u!)

		setNeedsUpdateOfPrefersPointerLocked()

		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)

		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true
		// the stream sits on black in either theme; letterbox bars and the trackpad below show through
		view.backgroundColor = .black

		// All gestures (cursor, pinch-zoom, two-finger scroll) are handled in the
		// ParsecTouchInputDelegate methods below, driven by touchOverlay's raw touches.

		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0, 2]
		// Let the overlay see the real touch end so no phantom finger lingers.
		singleFingerTapGestureRecognizer.cancelsTouchesInView = false
		singleFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		twoFingerTapGestureRecognizer.allowedTouchTypes = [0]
		twoFingerTapGestureRecognizer.cancelsTouchesInView = false
		twoFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
		//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)

		let threeFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleThreeFinderTap(_:)))
		threeFingerTapGestureRecognizer.numberOfTouchesRequired = 3
		threeFingerTapGestureRecognizer.allowedTouchTypes = [0]
		threeFingerTapGestureRecognizer.cancelsTouchesInView = false
		threeFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(threeFingerTapGestureRecognizer)

		let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
		longPressGestureRecognizer.numberOfTouchesRequired = 1
		longPressGestureRecognizer.allowedTouchTypes = [0, 2]
		longPressGestureRecognizer.allowableMovement = 40
		// Don't cancel the overlay's touch, so the click-hold button can be released on lift.
		longPressGestureRecognizer.cancelsTouchesInView = false
		view.addGestureRecognizer(longPressGestureRecognizer)

		menuEdgeSwipe = addMenuEdgeSwipe(.left)
		menuEdgeSwipeRight = addMenuEdgeSwipe(.right)

		// half-folding changes the reserved fold region without changing bounds
		// the iOS 27.1 SDK (Xcode 27, Swift 6.4) has the fold APIs; CI's older Xcode builds without them
		#if compiler(>=6.4)
		if #available(iOS 27.1, *) {
			view.addInteraction(UIHingeInteraction { [weak self] _, _ in self?.view.setNeedsLayout() })
		}
		#endif

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillShow),
			name: UIResponder.keyboardWillShowNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(inputWasReleased),
			name: NSNotification.Name("ParsecInputReleased"),
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillHide),
			name: UIResponder.keyboardWillHideNotification,
			object: nil
		)

		for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
			NotificationCenter.default.addObserver(self, selector: #selector(hardwareKeyboardChanged), name: name, object: nil)
		}
		// a mouse or trackpad (Magic Keyboard) takes over from the trackpad below the picture
		for name in [Notification.Name.GCMouseDidConnect, .GCMouseDidDisconnect] {
			NotificationCenter.default.addObserver(self, selector: #selector(mouseChanged), name: name, object: nil)
		}

		// Backgrounding / Control Center / system alerts can orphan touches; flush on resign.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillResignActive),
			name: UIApplication.willResignActiveNotification,
			object: nil
		)

	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		// sizing happens in viewDidLayoutSubviews, which also catches fold and split view resizes

        // Reset accessory view to ensure correct width in new orientation
        clearToolbarModifiers(sendToHost: true)
        keyboardAccessoriesView = nil
        if keyboardVisible {
            configureKeyPlacement()
            reloadInputViews()
        }
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// folding or unfolding with the keyboard up moves the keys without a size change
		if keyboardVisible && isFirstResponder {
			let before = keysInShortcutBar
			configureKeyPlacement()
			if before != keysInShortcutBar { reloadInputViews() }
		}
		// glkView/contentView get sized from possibly-stale bounds in viewDidLoad and have no
		// autoresizing, so the stream renders in a corner until layout re-applies the size.
		// only acts when the stream frame changes (rotation, fold / unfold, split view, half fold).
		guard scrollView != nil else { return }
		let layout = streamLayout()
		let frame = layout.picture
		var toolbar: CGRect?
		if let deck = layout.trackpad {
			// the toolbar takes the bottom band of the deck, the trackpad the rest
			let bar = deck.height > Self.deckToolbarHeight + 80 ? Self.deckToolbarHeight : 0
			trackpad.frame = CGRect(x: deck.minX, y: deck.minY, width: deck.width, height: deck.height - bar)
			toolbar = bar > 0 ? CGRect(x: deck.minX, y: deck.maxY - bar, width: deck.width, height: bar) : nil
			trackpad.isHidden = false
		} else if !trackpad.isHidden {
			trackpad.reset()
			trackpad.isHidden = true
		}
		if toolbar != lastDeckToolbar {
			lastDeckToolbar = toolbar
			onDeckToolbarChanged?(toolbar)
		}
		guard frame.width > 0, frame.height > 0, frame != lastLaidOutFrame else { return }
		// a held finger, glide or zoom offset would keep mapping against the old size
		if lastLaidOutFrame != .zero { flushAllTouches() }
		lastLaidOutFrame = frame
		// keyboard pinning was computed for the old frame; the keyboard re-posts show for the new one
		pinnedToKeyboard = false
		keyboardCoversPicture = false
		scrollView.contentInset = .zero
		updatePanHandle()
		scrollView.zoomScale = 1.0
		scrollView.frame = frame
		scrollView.contentOffset = .zero
		glkView.updateSize(width: frame.width, height: frame.height)
		contentView.frame.size = frame.size
		scrollView.contentSize = frame.size
		CParsec.setFrame(frame.width, frame.height, screenScale)
		positionCursorOverlay()
	}

	// the whole view, or only the half above the fold when half open like a laptop,
	// leaving the lower half for the keyboard (and touchpad mode, which works anywhere)
	func streamFrame() -> CGRect { streamLayout().picture }

	// where the picture goes, and the trackpad below it when there is one: the half fold's lower half,
	// or the space a portrait screen leaves under a top-aligned picture
	func streamLayout() -> (picture: CGRect, trackpad: CGRect?) {
		let b = view.bounds
		let padBottom = b.maxY - view.safeAreaInsets.bottom
		if let fold = halfFold() {
			let picture = CGRect(x: 0, y: 0, width: b.width, height: fold.minY)
			let pad = CGRect(x: 0, y: fold.maxY, width: b.width, height: padBottom - fold.maxY)
			return (picture, SettingsHandler.trackpadBelowPicture && pad.height > 60 ? pad : nil)
		}
		// ponytail: a vertical fold (book posture) keeps the stream across both halves
		let host = CGSize(width: CGFloat(CParsec.hostWidth), height: CGFloat(CParsec.hostHeight))
		// ponytail: the half fold keeps its pad with a mouse attached, its lower half would sit empty
		if SettingsHandler.trackpadBelowPicture, GCMouse.mice().isEmpty,
		   let picture = pictureAboveTrackpad(in: b, topInset: view.safeAreaInsets.top, host: host, minTrackpad: 120) {
			return (picture, CGRect(x: 0, y: picture.maxY, width: b.width, height: padBottom - picture.maxY))
		}
		return (b, nil)
	}

	// the hinge when half open like a laptop
	func halfFold() -> CGRect? {
		#if compiler(>=6.4)
		if #available(iOS 27.1, *),
		   let fold = view.reservedRegions(kind: .division).first(where: { $0.isActive && $0.frame.width > $0.frame.height }),
		   fold.frame.minY > view.bounds.height / 4 {
			return fold.frame
		}
		#endif
		return nil
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		UIApplication.shared.isIdleTimerDisabled = true
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		if keyboardVisible || GCKeyboard.coalesced != nil {
			becomeFirstResponder()
		}
		// (Pinch-to-zoom is driven manually via touchOverlay; the scroll view's pinch stays off.)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		UIApplication.shared.isIdleTimerDisabled = false
		stopMomentum()
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
	}
	
	
	private var repeatTimer: Timer?
	private var repeatKeyCode: Int = -1
	private var optCmdRemapActive = false
	private var altKeyHeld = false

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = true
			}

			if SettingsHandler.optionAsCommand && !isModifierKey(key.keyCode) && (altKeyHeld || key.modifierFlags.contains(.alternate)) {
				if !optCmdRemapActive {
					CParsec.sendKeyboardMessage(keyCode: 226, pressed: false)
					CParsec.sendKeyboardMessage(keyCode: 230, pressed: false)
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: true)
					optCmdRemapActive = true
				}
				let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
				CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: true)
				startKeyRepeat(keyCode: code)
				continue
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: true))

			if !isModifierKey(key.keyCode) {
				startKeyRepeat(keyCode: KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode))
			}
		}
	}

	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if optCmdRemapActive {
				if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
					altKeyHeld = false
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: false)
					optCmdRemapActive = false
					continue
				}
				if !isModifierKey(key.keyCode) {
					let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
					CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: false)
					if code == repeatKeyCode { stopKeyRepeat() }
					continue
				}
			}

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = false
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: false))

			let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
			if code == repeatKeyCode {
				stopKeyRepeat()
			}
		}
	}

	override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		// iOS sends this instead of pressesEnded when a press is interrupted (e.g. backgrounding
		// mid-hold) — without cleanup the host keeps keys held (stuck paste, stuck modifier).
		CParsec.sendReleaseMessage()
		resetKeyState()
	}

	private func startKeyRepeat(keyCode: Int) {
		stopKeyRepeat()
		repeatKeyCode = keyCode

		repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self = self else { return }
				self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
					MainActor.assumeIsolated {
						guard let self = self else { return }
						CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: false)
						CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: true)
					}
				}
			}
		}
	}

	private func stopKeyRepeat() {
		repeatTimer?.invalidate()
		repeatTimer = nil
		repeatKeyCode = -1
	}

	func resetKeyState() {
		stopKeyRepeat()
		optCmdRemapActive = false
		altKeyHeld = false
	}

	private func isModifierKey(_ keyCode: UIKeyboardHIDUsage) -> Bool {
		switch keyCode {
		case .keyboardLeftControl, .keyboardLeftShift, .keyboardLeftAlt, .keyboardLeftGUI,
			 .keyboardRightControl, .keyboardRightShift, .keyboardRightAlt, .keyboardRightGUI,
			 .keyboardCapsLock:
			return true
		default:
			return false
		}
	}

	// A hardware keyboard types straight to the host: the view takes key presses as soon as one is
	// attached, without raising the key row. Unplugged, it lets go, or the on-screen keyboard would pop up.
	@objc func hardwareKeyboardChanged() {
		guard !keyboardVisible, view.window != nil else { return }
		if GCKeyboard.coalesced != nil {
			// the half fold's shortcut-bar keys would come back with it
			configureKeyPlacement()
			becomeFirstResponder()
		} else {
			resignFirstResponder()
		}
	}

	@objc func mouseChanged() {
		view.setNeedsLayout()
	}

	@objc func keyboardWillShow(notification: NSNotification) {
		// keyboard notifications are app wide; another window's text field is not ours
		// first responder only for a hardware keyboard: whatever iPadOS shows there isn't our keyboard
		guard isFirstResponder, keyboardVisible else { return }
		checkShortcutBar()
		if let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
			let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
			let scrollFrameInView = scrollView.convert(scrollView.bounds, to: view)
			let intersection = scrollFrameInView.intersection(keyboardFrameInView)
			let coversBottomEdge = !intersection.isNull && intersection.maxY >= scrollFrameInView.maxY - 1
			let height = coversBottomEdge ? intersection.height : 0
			keyboardHeight = height
            keyboardVisible = true

            // Allow scrolling past current bottom to see hidden content
            scrollView.contentInset.bottom = height

			if scrollView.zoomScale <= 1.0, let shift = pictureShiftAboveKeyboard(height - accessoryClearBand) {
				keyboardCoversPicture = false
				updatePanHandle()
				pinnedToKeyboard = true
				scrollView.contentInset.top = max(0, -shift)
				scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: shift), animated: true)
				onKeyboardVisibilityChanged?(true)
				return
			}
			var baseY = scrollView.contentOffset.y
			if pinnedToKeyboard {
				pinnedToKeyboard = false
				scrollView.contentInset.top = 0
				baseY = 0
			}
			keyboardCoversPicture = height > 0
			updatePanHandle()
			if height > 0 && SettingsHandler.cursorMode == .direct {
				onKeyboardCoversPicture?()
			}
			if SettingsHandler.cursorMode == .direct {
				let bottomY = max(0, scrollView.contentSize.height - scrollView.bounds.height + height)
				scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: bottomY), animated: true)
				onKeyboardVisibilityChanged?(true)
				return
			}

            // Automatic scroll up only if mouse is in the bottom half of the screen
            let mouseY = CGFloat(CParsec.mouseInfo.mouseY)
            let screenMidY = scrollView.bounds.height / 2.1

            if mouseY > screenMidY {
                 let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + height)
                 let newOffsetY = min(maxOffsetY, baseY + height / 1.25)

                 scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newOffsetY), animated: true)

            } else if baseY != scrollView.contentOffset.y {
				scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: baseY), animated: true)
			}
		}
		onKeyboardVisibilityChanged?(true)
	}

	var accessoryClearBand: CGFloat {
		keyboardAccessoriesView?.subviews.first?.frame.minY ?? 0
	}

	func pictureShiftAboveKeyboard(_ keyboard: CGFloat) -> CGFloat? {
		let w = scrollView.bounds.width, h = scrollView.bounds.height
		guard keyboard > 0, CParsec.hostWidth > 0, CParsec.hostHeight > 0 else { return nil }
		let picture = min(h, w * CGFloat(CParsec.hostHeight / CParsec.hostWidth))
		guard picture <= h - keyboard else { return nil }
		return keyboard - (h - picture) / 2
	}

	func updatePanHandle() {
		setPanHandleVisible(keyboardCoversPicture && SettingsHandler.cursorMode == .direct)
	}

	func setPanHandleVisible(_ visible: Bool) {
		guard let handle = panHandle else { return }
		handle.isHidden = !visible
		setPanHandleAxes()
		layoutKeyBar()
	}

	func setPanHandleAxes() {
		guard let handle = panHandle, !handle.isHidden else { return }
		let zoomed = scrollView.zoomScale > 1.01
		let label = zoomed ? String(localized: "Move screen in any direction") : String(localized: "Move screen up or down")
		guard handle.accessibilityLabel != label else { return }
		handle.image = UIImage(systemName: zoomed ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.up.and.down")
		handle.accessibilityLabel = label
	}

	func layoutKeyBar() {
		guard let handle = panHandle, let keys = keyScrollView, let bar = keys.superview else { return }
		let inset = bar.safeAreaInsets
		handle.frame.origin.x = 4 + inset.left
		let left = (handle.isHidden ? 8 : 48) + inset.left
		keys.frame = CGRect(x: left, y: 0, width: bar.bounds.width - 72 - left - inset.right, height: 44)
		keyBarDone?.frame.origin.x = bar.bounds.width - 70 - inset.right
	}

	@objc func handlePanHandle(_ gesture: UIPanGestureRecognizer) {
		if gesture.state == .began {
			panStartOffset = scrollView.contentOffset
		}
		let t = gesture.translation(in: view)
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
		let x = min(max(0, panStartOffset.x - t.x), maxX)
		let y = min(max(-scrollView.contentInset.top, panStartOffset.y - t.y), maxY)
		scrollView.setContentOffset(CGPoint(x: x, y: y), animated: false)
		positionCursorOverlay()
	}

	@objc func handlePanHandleDoubleTap(_ gesture: UITapGestureRecognizer) {
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
		let y: CGFloat = scrollView.contentOffset.y < maxY / 2 ? maxY : 0
		scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		guard keyboardVisible else { return }
		let appliedHeight = keyboardHeight
		keyboardHeight = 0.0
        keyboardVisible = false
		keyboardCoversPicture = false
		setPanHandleVisible(false)
		if pinnedToKeyboard {
			pinnedToKeyboard = false
			scrollView.contentInset = .zero
			scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: 0), animated: true)
			onKeyboardVisibilityChanged?(false)
			return
		}

        // Restore inset
        scrollView.contentInset.bottom = 0

        // Transform cleanup (just in case)
        view.transform = .identity

        // Automatic scroll down (reverse of show). Not gated on width > height any more:
        // show scrolls in every orientation, and a near-square foldable screen flips that check.
		// Undo only the overlap show applied, not the full keyboard height (0 below a half fold).
		let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
		let newOffsetY = min(maxOffsetY, max(0, scrollView.contentOffset.y - appliedHeight))
		if appliedHeight > 0, newOffsetY != scrollView.contentOffset.y {
			scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newOffsetY), animated: true)
		}
		onKeyboardVisibilityChanged?(false)
	}

}

extension ParsecViewController: UIGestureRecognizerDelegate {

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
	}

	// the delay stops a direct mode swipe from clicking at the edge first
	private func addMenuEdgeSwipe(_ edge: UIRectEdge) -> UIScreenEdgePanGestureRecognizer {
		let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleMenuEdgeSwipe(_:)))
		edgeSwipe.edges = edge
		edgeSwipe.maximumNumberOfTouches = 1
		edgeSwipe.allowedTouchTypes = [0]
		edgeSwipe.delaysTouchesBegan = true
		edgeSwipe.isEnabled = false
		view.addGestureRecognizer(edgeSwipe)
		return edgeSwipe
	}

	// left brings back a hidden menu button, slide over owns the right edge
	func updateMenuEdgeSwipe(menuHidden: Bool) {
		menuEdgeSwipe?.isEnabled = menuHidden || SettingsHandler.menuSwipeEdge == .left
		menuEdgeSwipeRight?.isEnabled = SettingsHandler.menuSwipeEdge == .right
	}

	// switching it off mid swipe would hand the held touch to the stream
	@objc private func handleMenuEdgeSwipe(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
		switch gestureRecognizer.state {
		case .began:
			flushAllTouches()
			onMenuEdgeSwipe?()
		case .ended, .cancelled, .failed:
			updateMenuEdgeSwipe(menuHidden: false)
		default:
			break
		}
	}

	@objc func handlePinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
		// Pinch is handled by UIScrollView
	}

	// MARK: - Manual touch handling (ParsecTouchInputDelegate)
	// touchOverlay delivers raw touches here. One finger drives the mouse cursor; two fingers are
	// classified once per gesture into either pinch-zoom or host scroll-wheel (never both), so the
	// gestures never fight. No UIScrollView gesture recognizer is in the loop.

	func parsecTouchesUpdated(_ touches: Set<UITouch>, moved: Bool) {
		// fingers still down from before a flush must not start a fresh click where they now are
		if waitForLift {
			// a lift the system swallowed would otherwise lock touch out, so give up waiting after 2 s
			if touches.isEmpty || CACurrentMediaTime() - waitForLiftSince > 2 { waitForLift = false }
			return
		}
		// half fold, direct mode: the lower half is not picture, so a touch there must not click the bottom edge
		let touches = SettingsHandler.cursorMode == .direct && scrollView.frame != view.bounds
			? touches.filter { scrollView.frame.contains($0.location(in: view)) } : touches
		let oldCount = activeTouches.count
		// Rebuild from the event each time (keeping order) so a cancelled touch can't leave a stale one.
		var ordered = activeTouches.filter { touches.contains($0) }
		for t in touches where !ordered.contains(t) {
			ordered.append(t)
			touchOrigins[t] = t.location(in: view)
		}
		// Sweep a ghost (an OS-dropped lift lingering as .stationary) only while another finger actively
		// moves - a resting or just-tapped finger is never swept, so taps and held fingers stay safe.
		var sweptGhost = false
		if ordered.count >= 2 && !clickHoldActive,
		   let newest = ordered.max(by: { $0.timestamp < $1.timestamp }) {
			let origin = touchOrigins[newest] ?? newest.location(in: view)
			let here = newest.location(in: view)
			if hypot(here.x - origin.x, here.y - origin.y) > staleMoveSlop {
				let fresh = ordered.filter { newest.timestamp - $0.timestamp < staleTouchThreshold }
				if fresh.count < ordered.count { ordered = fresh; sweptGhost = true }
			}
		}
		activeTouches = ordered
		touchOrigins = touchOrigins.filter { activeTouches.contains($0.key) }
		if sweptGhost && activeTouches.count == 1 {
			// Recover the surviving finger as a live cursor instead of inert two-finger residual.
			stopMomentum()
			twoFingerResidual = false
			twoFingerMode = .undecided
			startCursor()
		} else if activeTouches.count != oldCount {
			handleTouchCountChange(old: oldCount, new: activeTouches.count)
		}
		if moved { handleActiveTouchesMoved() }
	}

	private func handleTouchCountChange(old: Int, new: Int) {
		edgeScrollActive = false
		if new > old { stopMomentum() }   // any new finger cancels an in-progress glide
		if new == 0 {
			let flingCursor = (old == 1) && isDragging && !twoFingerResidual && !clickHoldActive
			let flingScroll = (old >= 2) && (twoFingerMode == .scroll)
			releaseClickHoldIfNeeded()   // defensive: the left button must never stay stuck down
			endCursorIfNeeded()
			isDragging = false
			twoFingerResidual = false
			twoFingerMode = .undecided
			if flingCursor { startCursorMomentum() }
			if flingScroll { startScrollMomentum() }
		} else if new == 1 {
			if old >= 2 {
				// Leftover finger after a two-finger gesture: stay inert until full lift so it
				// doesn't jump the cursor.
				if twoFingerMode == .scroll { startScrollMomentum() }
				twoFingerResidual = true
				twoFingerMode = .undecided
			} else if old == 0 {
				startCursor()
			}
		} else if new >= 2 {
			releaseClickHoldIfNeeded()   // can't keep the button held during a two-finger gesture
			cancelDirectPress()          // the first finger was the start of this gesture, not a click
			if isDragging { endCursorIfNeeded(); isDragging = false }
			beginTwoFinger()
		}
	}

	private func releaseClickHoldIfNeeded() {
		if clickHoldActive {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false)
			clickHoldActive = false
		}
	}

	@objc private func appWillResignActive() {
		flushAllTouches()
		trackpad?.reset()
	}

	// Drop all touch state and release any held button so nothing sticks when backgrounded.
	private func flushAllTouches() {
		stopMomentum()
		releaseClickHoldIfNeeded()
		cancelDirectPress()
		endCursorIfNeeded()
		waitForLift = !activeTouches.isEmpty
		waitForLiftSince = CACurrentMediaTime()
		isDragging = false
		twoFingerResidual = false
		twoFingerMode = .undecided
		activeTouches = []
	}

	private func startCursor() {
		isDragging = true
		twoFingerResidual = false
		cursorDidMoveThisTouch = false
		singleTouchStartScreen = activeTouches.first?.location(in: view) ?? .zero
		if SettingsHandler.cursorMode == .direct {
			if let t = activeTouches.first {
				cursorContentPos = clampToContent(contentView.convert(t.location(in: view), from: view))
				CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
				positionCursorOverlay()
			}
			// the press waits a beat: a second finger landing in that time makes this a two-finger
			// gesture (right click, scroll, zoom), not a stray left click
			directClick.begin()
			let timer = DispatchWorkItem { [weak self] in self?.sendDirectPress() }
			directPressTimer = timer
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: timer)
		}
	}

	private func sendDirectPress() {
		directPressTimer?.cancel()
		directPressTimer = nil
		if directClick.press() {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true)
		}
	}

	private func cancelDirectPress() {
		directPressTimer?.cancel()
		directPressTimer = nil
		directClick.cancel()
	}

	private func endCursorIfNeeded() {
		guard isDragging && SettingsHandler.cursorMode == .direct else { return }
		directPressTimer?.cancel()
		directPressTimer = nil
		let (press, release) = directClick.lift()
		if press { CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true) }
		if release { CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false) }
	}

	private func beginTwoFinger() {
		twoFingerMode = .undecided
		twoFingerDidMove = false
		accumulatedScrollY = 0.0
		let d = twoFingerDistanceAndMidpoint()
		startPinchDistance = d.distance
		lastPinchDistance = d.distance
		startTwoFingerMidpoint = d.midpoint
		lastTwoFingerMidpoint = d.midpoint
	}

	private func twoFingerDistanceAndMidpoint() -> (distance: CGFloat, midpoint: CGPoint) {
		let pts = activeTouches.prefix(2).map { $0.location(in: view) }
		guard pts.count == 2 else { return (0, pts.first ?? .zero) }
		let dx = pts[1].x - pts[0].x
		let dy = pts[1].y - pts[0].y
		let mid = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
		return (hypot(dx, dy), mid)
	}

	private func handleActiveTouchesMoved() {
		if (isDragging || clickHoldActive), !twoFingerResidual, activeTouches.count == 1, let t = activeTouches.first {
			moveCursor(with: t)
		} else if activeTouches.count >= 2 {
			handleTwoFinger()
		}
	}

	private func moveCursor(with t: UITouch) {
		let zoom = scrollView.zoomScale
		let loc = t.location(in: view)
		let prev = t.previousLocation(in: view)
		if hypot(loc.x - singleTouchStartScreen.x, loc.y - singleTouchStartScreen.y) > tapMoveSlop {
			cursorDidMoveThisTouch = true
		}

		if CParsec.mouseInfo.mousePositionRelative {
			// Host has captured the pointer (e.g. a game): send true relative motion instead.
			let s = CGFloat(mouseSensitivity) / zoom
			CParsec.sendMouseDelta(hostInt((loc.x - prev.x) * s), hostInt((loc.y - prev.y) * s))
			return
		}

		if SettingsHandler.cursorMode == .direct {
			cursorContentPos = clampToContent(contentView.convert(loc, from: view))
			// a real drag can't wait for the held-back press
			if directClick.pending && cursorDidMoveThisTouch {
				CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
				sendDirectPress()
			}
		} else {
			// Relative finger movement, predicted locally; sensitivity scales down with zoom so the
			// cursor tracks the visible finger.
			let s = CGFloat(mouseSensitivity) / zoom
			let dcx = (loc.x - prev.x) * s
			let dcy = (loc.y - prev.y) * s
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + dcx, y: cursorContentPos.y + dcy))
			// Smoothed velocity so a quick flick keeps gliding after the finger lifts.
			let now = CACurrentMediaTime()
			let dt = CGFloat(now - lastCursorMoveTime)
			if dt > 0.0005 && dt < 0.1 {
				cursorVelocity = CGPoint(x: cursorVelocity.x * 0.4 + (dcx / dt) * 0.6,
										 y: cursorVelocity.y * 0.4 + (dcy / dt) * 0.6)
			}
			lastCursorMoveTime = now
		}
		// Command the host to the ABSOLUTE predicted position (not a delta) so the host cursor can't
		// crawl behind network round-trips - clicks always land where the cursor is drawn.
		CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
		if SettingsHandler.cursorMode == .direct {
			edgeScrollPoint = loc
			if cursorDidMoveThisTouch && edgeScrollVelocity(at: loc) != .zero {
				if !edgeScrollActive { edgeScrollLastTick = 0 }
				edgeScrollActive = true
				ensureMomentumLink()
			}
		} else {
			centerViewportOnCursorPos()
			positionCursorOverlay()
			keepCursorAboveKeyboard()
		}
		positionCursorOverlay()
	}

	private func handleTwoFinger() {
		let d = twoFingerDistanceAndMidpoint()
		if twoFingerMode == .undecided {
			let distDelta = abs(d.distance - startPinchDistance)
			let midDelta = hypot(d.midpoint.x - startTwoFingerMidpoint.x, d.midpoint.y - startTwoFingerMidpoint.y)
			let deadZone: CGFloat = 12.0
			if distDelta > deadZone || midDelta > deadZone {
				twoFingerMode = (distDelta > midDelta && zoomEnabled) ? .zoom : .scroll
				twoFingerDidMove = true
			}
		}
		switch twoFingerMode {
		case .zoom:
			if lastPinchDistance > 0 {
				applyZoom(to: scrollView.zoomScale * (d.distance / lastPinchDistance), anchorInView: CGPoint(x: d.midpoint.x - scrollView.frame.minX, y: d.midpoint.y - scrollView.frame.minY))
			}
		case .scroll:
			scrollWheel(byFingers: CGPoint(x: 0, y: d.midpoint.y - lastTwoFingerMidpoint.y))
		case .undecided:
			break
		}
		lastPinchDistance = d.distance
		lastTwoFingerMidpoint = d.midpoint
	}

	// two fingers moving by this much (screen points) turn the host's wheel, with the reverse setting
	func scrollWheel(byFingers delta: CGPoint) {
		let direction: Float = SettingsHandler.reverseScrollDirection ? -1.0 : 1.0
		let contribution = Float(delta.y) * scrollWheelSpeed * direction
		accumulatedScrollY += contribution
		let intScrollY = hostInt(accumulatedScrollY)
		if intScrollY != 0 {
			CParsec.sendWheelMsg(x: 0, y: intScrollY)
			accumulatedScrollY -= Float(intScrollY)
		}
		// sideways: fingers moving right bring in what's on the left
		accumulatedScrollX -= Float(delta.x) * scrollWheelSpeed * direction
		let intScrollX = hostInt(accumulatedScrollX)
		if intScrollX != 0 {
			CParsec.sendWheelMsg(x: intScrollX, y: 0)
			accumulatedScrollX -= Float(intScrollX)
		}
		// Track scroll velocity for a little post-flick momentum.
		let snow = CACurrentMediaTime()
		let sdt = Float(snow - lastScrollMoveTime)
		if sdt > 0.0005 && sdt < 0.1 {
			scrollVelocity = scrollVelocity * 0.4 + (contribution / sdt) * 0.6
		}
		lastScrollMoveTime = snow
	}

	private func startCursorMomentum(fromTrackpad: Bool = false) {
		guard SettingsHandler.cursorMode == .touchpad || fromTrackpad, !CParsec.mouseInfo.mousePositionRelative else { return }
		guard CACurrentMediaTime() - lastCursorMoveTime < 0.06 else { return }   // finger was still moving at release
		guard hypot(cursorVelocity.x, cursorVelocity.y) > flingMinSpeed else { return }
		// Less glide when zoomed out: at 1x the cursor crosses the screen instead of panning the view.
		let glideScale = min(1.0, 0.3 + 0.7 * (scrollView.zoomScale - 1.0))
		cursorVelocity.x *= glideScale
		cursorVelocity.y *= glideScale
		cursorMomentumActive = true
		ensureMomentumLink()
	}

	private func startScrollMomentum() {
		guard CACurrentMediaTime() - lastScrollMoveTime < 0.06 else { return }
		guard abs(scrollVelocity) > scrollStartSpeed else { return }
		scrollMomentumActive = true
		ensureMomentumLink()
	}

	private func ensureMomentumLink() {
		if momentumLink == nil {
			let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
			link.add(to: .main, forMode: .common)
			momentumLink = link
		}
	}

	func stopMomentum() {
		cursorMomentumActive = false
		scrollMomentumActive = false
		edgeScrollActive = false
		cursorVelocity = .zero
		scrollVelocity = 0
		momentumLink?.invalidate()
		momentumLink = nil
	}

	@objc func momentumTick(_ link: CADisplayLink) {
		let dt = CGFloat(link.targetTimestamp - link.timestamp)
		if dt <= 0 { return }
		var stillActive = false

		if cursorMomentumActive {
			let decay = CGFloat(pow(cursorDecayPerSec, Double(dt)))
			cursorVelocity.x *= decay
			cursorVelocity.y *= decay
			let before = cursorContentPos
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + cursorVelocity.x * dt,
													  y: cursorContentPos.y + cursorVelocity.y * dt))
			if !CParsec.mouseInfo.mousePositionRelative {
				CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
			}
			centerViewportOnCursorPos()
			positionCursorOverlay()
			let stalled = abs(cursorContentPos.x - before.x) < 0.05 && abs(cursorContentPos.y - before.y) < 0.05
			if hypot(cursorVelocity.x, cursorVelocity.y) < cursorStopSpeed || stalled {
				cursorMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if scrollMomentumActive {
			scrollVelocity *= Float(pow(scrollDecayPerSec, Double(dt)))
			accumulatedScrollY += scrollVelocity * Float(dt)
			let i = hostInt(accumulatedScrollY)
			if i != 0 {
				CParsec.sendWheelMsg(x: 0, y: i)
				accumulatedScrollY -= Float(i)
			}
			if abs(scrollVelocity) < scrollStopSpeed {
				scrollMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if edgeScrollActive {
			let elapsed = edgeScrollLastTick > 0 ? min(CGFloat(link.timestamp - edgeScrollLastTick), 0.1) : dt
			edgeScrollLastTick = link.timestamp
			if stepEdgeScroll(elapsed) {
				stillActive = true
			} else {
				edgeScrollActive = false
			}
		}

		if !stillActive { stopMomentum() }
	}

	// Manually zoom the scroll view around a screen-space anchor (the pinch midpoint), keeping the
	// content point under the anchor fixed. Replaces the scroll view's own pinch recognizer.
	private func applyZoom(to targetScale: CGFloat, anchorInView anchor: CGPoint) {
		let oldZoom = scrollView.zoomScale
		let newZoom = min(max(targetScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
		guard abs(newZoom - oldZoom) > 0.0001 else { return }
		let off = scrollView.contentOffset
		let contentX = (anchor.x + off.x) / oldZoom
		let contentY = (anchor.y + off.y) / oldZoom
		scrollView.zoomScale = newZoom
		setPanHandleAxes()
		if pinnedToKeyboard {
			pinnedToKeyboard = false
			scrollView.contentInset.top = 0
			keyboardCoversPicture = keyboardHeight > 0
			updatePanHandle()
		}
		var newOff = CGPoint(x: contentX * newZoom - anchor.x, y: contentY * newZoom - anchor.y)
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
		newOff.x = min(max(0, newOff.x), maxX)
		newOff.y = min(max(0, newOff.y), maxY)
		scrollView.setContentOffset(newOff, animated: false)
		// Park the cursor at the viewport centre after zooming so a later drag doesn't snap the view.
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let centerX = (scrollView.bounds.width / 2 + scrollView.contentOffset.x) / newZoom
		let centerY = ((scrollView.bounds.height - bottomInset) / 2 + scrollView.contentOffset.y) / newZoom
		cursorContentPos = clampToContent(CGPoint(x: centerX, y: centerY))
		if !CParsec.mouseInfo.mousePositionRelative {
			CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
		}
		positionCursorOverlay()
	}

	private func clampToContent(_ p: CGPoint) -> CGPoint {
		let w = contentView.bounds.width
		let h = contentView.bounds.height
		return CGPoint(x: min(max(0, p.x), w), y: min(max(0, p.y), h))
	}

	// Places the cursor overlay at the cursor's content position projected into screen space,
	// drawn at full Cursor Scale (no zoom division) so it stays crisp and constant-sized.
	func positionCursorOverlay() {
		guard let u = u else { return }
		let zoom = scrollView.zoomScale
		let off = scrollView.contentOffset
		// u sits in the view, the picture may not start at its top (portrait with the trackpad below)
		let screenX = cursorContentPos.x * zoom - off.x + scrollView.frame.minX
		let screenY = cursorContentPos.y * zoom - off.y + scrollView.frame.minY
		let cs = CGFloat(SettingsHandler.cursorScale)
		let hotX = CGFloat(CParsec.mouseInfo.cursorHotX) * cs
		let hotY = CGFloat(CParsec.mouseInfo.cursorHotY) * cs
		let w = CGFloat(CParsec.mouseInfo.cursorWidth) * cs
		let h = CGFloat(CParsec.mouseInfo.cursorHeight) * cs
		u.frame = CGRect(x: screenX - hotX, y: screenY - hotY, width: w, height: h)
	}

	// the trackpad handles its own taps and holds
	private func onTrackpad(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		!trackpad.isHidden && trackpad.frame.contains(gestureRecognizer.location(in: view))
	}

	@objc func handleSingleFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		if onTrackpad(gestureRecognizer) { return }
		// Only click if the finger stayed put; a moved finger was a cursor nudge, not a tap.
		if cursorDidMoveThisTouch { return }
		if SettingsHandler.cursorMode == .direct { return }
		let location = gestureRecognizer.location(in: gestureRecognizer.view)
		let adjustedLocation = contentView.convert(location, from: view)
		touchController.onTap(typeOfTap: 1, location: adjustedLocation)
	}

	@objc func handleTwoFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		if onTrackpad(gestureRecognizer) { return }
		// A two-finger TAP is a right click; if the fingers moved (pinch/scroll) it wasn't a tap.
		if twoFingerDidMove { return }
		// dont leak a right-click to the host while backgrounding (app switch) or after a disconnect
		guard UIApplication.shared.applicationState == .active,
			  ParsecBackgroundManager.shared.hasActiveConnection else { return }

		let location: CGPoint
		switch SettingsHandler.rightClickPosition {
		case .firstFinger:
			location = gestureRecognizer.location(ofTouch: 0, in: gestureRecognizer.view)
			case .secondFinger:
			location = gestureRecognizer.location(ofTouch: 1, in: gestureRecognizer.view)
		default:
			location = gestureRecognizer.location(in: gestureRecognizer.view)
		}

		let adjustedLocation = contentView.convert(location, from: view)
		touchController.onTap(typeOfTap: 3, location: adjustedLocation)
	}

	@objc func handleThreeFinderTap(_ gestureRecognizer: UITapGestureRecognizer) {
		if onTrackpad(gestureRecognizer) { return }
		setKeyboardVisible(!keyboardVisible)
	}

	@objc func handleLongPress(_ gestureRecognizer: UIGestureRecognizer) {
		if SettingsHandler.cursorMode != .touchpad {
			return
		}
		if gestureRecognizer.state == .began && onTrackpad(gestureRecognizer) { return }
		switch gestureRecognizer.state {
		case .began:
			// Click-and-hold (file drag): hold the left button; the overlay keeps moving the cursor.
			clickHoldActive = true
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true)
		case .ended, .cancelled, .failed:
			releaseClickHoldIfNeeded()
		default:
			break
		}
	}

    // UIScrollViewDelegate
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return contentView
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		positionCursorOverlay()
	}

	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		// Centering is handled on cursor movement (updateImage) and at the end of a pinch.
	}

	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		centerViewportOnCursorPos()
	}

	func keepCursorAboveKeyboard() {
		guard scrollView.zoomScale <= 1.0, keyboardVisible, scrollView.contentInset.bottom > 0, !pinnedToKeyboard,
			  SettingsHandler.cursorMode != .direct, let u = u, !u.isHidden else { return }
		// the cursor frame is in view coordinates, the rest of this in the picture's
		let cursorFrame = u.frame.offsetBy(dx: -scrollView.frame.minX, dy: -scrollView.frame.minY)
		let visibleBottom = scrollView.bounds.height - keyboardHeight
		let margin = min(50, max(0, (visibleBottom - cursorFrame.height) / 2 - 1))
		let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
		var target = scrollView.contentOffset.y
		if cursorFrame.maxY > visibleBottom - margin {
			target += cursorFrame.maxY - (visibleBottom - margin)
		} else if cursorFrame.minY < margin {
			target -= margin - cursorFrame.minY
		}
		target = min(max(0, target), maxOffsetY)
		guard target != scrollView.contentOffset.y else { return }
		scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
		positionCursorOverlay()
	}

	// Slides the viewport so the host cursor stays centered on screen while zoomed in,
	// clamped so the cursor can still reach the true edges of the host screen.
	func centerViewportOnCursorPos() {
		guard scrollView.zoomScale > 1.0 else { return }
		let zoom = scrollView.zoomScale
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let visibleWidth = scrollView.bounds.width
		let visibleHeight = scrollView.bounds.height - bottomInset
		let cursorX = cursorContentPos.x * zoom
		let cursorY = cursorContentPos.y * zoom
		var targetX = cursorX - visibleWidth / 2
		var targetY = cursorY - visibleHeight / 2
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
		targetX = min(max(0, targetX), maxX)
		targetY = min(max(0, targetY), maxY)
		scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
	}

	private func edgeScrollVelocity(at point: CGPoint) -> CGPoint {
		guard scrollView.zoomScale > 1.0 else { return .zero }
		// a view point, measured against the picture's edges
		let p = CGPoint(x: point.x - scrollView.frame.minX, y: point.y - scrollView.frame.minY)
		let visibleHeight = scrollView.bounds.height - (keyboardVisible ? keyboardHeight : 0.0)
		func axis(_ v: CGFloat, _ length: CGFloat) -> CGFloat {
			if v < edgeScrollMargin {
				return -min(1, (edgeScrollMargin - v) / edgeScrollMargin) * edgeScrollMaxSpeed
			}
			if v > length - edgeScrollMargin {
				return min(1, (v - (length - edgeScrollMargin)) / edgeScrollMargin) * edgeScrollMaxSpeed
			}
			return 0
		}
		return CGPoint(x: axis(p.x, scrollView.bounds.width), y: axis(p.y, visibleHeight))
	}

	private func stepEdgeScroll(_ dt: CGFloat) -> Bool {
		let v = edgeScrollVelocity(at: edgeScrollPoint)
		guard v != .zero, !CParsec.mouseInfo.mousePositionRelative else { return false }
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
		let off = scrollView.contentOffset
		let next = CGPoint(x: min(max(0, off.x + v.x * dt), maxX), y: min(max(0, off.y + v.y * dt), maxY))
		guard next != off else { return false }
		scrollView.setContentOffset(next, animated: false)
		cursorContentPos = clampToContent(contentView.convert(edgeScrollPoint, from: view))
		CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
		positionCursorOverlay()
		return true
	}

	func setZoomEnabled(_ enabled: Bool) {
		// Pinch is driven manually in touchOverlay; just gate it with this flag.
		zoomEnabled = enabled
		guard !enabled, scrollView.zoomScale > 1.0 else { return }
		UIView.animate(withDuration: 0.25, animations: {
			self.scrollView.zoomScale = 1.0
			self.scrollView.contentOffset = .zero
		}, completion: { _ in
			self.positionCursorOverlay()
		})
	}

}

extension ParsecViewController: UIPointerInteractionDelegate {
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		return UIPointerStyle.hidden()
	}

	func pointerInteraction(_ inter: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
		let loc = request.location
		if let iv = view!.hitTest(loc, with: nil) {
			let rect = view!.convert(iv.bounds, from: iv)
			let region = UIPointerRegion(rect: rect, identifier: iv.tag)
			return region
		}
		return nil
	}

}

// a keycap in the dark key row; a latched modifier turns white like the rest of the app
class KeyboardButton: UIButton {
	let keyText: String
	let isToggleable: Bool
	/// a shortcut sent as one press, for the ones iPadOS keeps for itself (⌘Tab, ⌘Space, ⌘H, screenshots)
	var combo: [UInt32] = []
	var isOn = false { didSet { restyle() } }
	override var isHighlighted: Bool { didSet { restyle() } }

	required init(keyText: String, isToggleable: Bool) {
		self.keyText = keyText
		self.isToggleable = isToggleable
		super.init(frame: .zero)
		layer.cornerRadius = 8
		layer.cornerCurve = .continuous
		overrideUserInterfaceStyle = .dark
		restyle()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func restyle() {
		backgroundColor = isOn ? .white : UIColor(white: isHighlighted ? 0.42 : 0.24, alpha: 1)
		setTitleColor(isOn ? .black : .white, for: .normal)
		tintColor = isOn ? .black : .white
	}
}

// MARK: - Virtual Keyboard
extension ParsecViewController: UIKeyInput, UITextInputTraits {
	var hasText: Bool {
		return true
	}

	var keyboardType: UIKeyboardType {
		get {
			return .asciiCapable
		}
		set {

		}
	}

	// passthrough keyboard: send raw input, dont let iOS autocorrect / smart-substitute / inject text
	var autocorrectionType: UITextAutocorrectionType {
		get { .no }
		set { }
	}
	var spellCheckingType: UITextSpellCheckingType {
		get { .no }
		set { }
	}
	var smartQuotesType: UITextSmartQuotesType {
		get { .no }
		set { }
	}
	var smartDashesType: UITextSmartDashesType {
		get { .no }
		set { }
	}
	var smartInsertDeleteType: UITextSmartInsertDeleteType {
		get { .no }
		set { }
	}
	var autocapitalizationType: UITextAutocapitalizationType {
		get { .none }
		set { }
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	// a modifier latched on the key row applies to the next key only, like sticky keys on a Mac
	func insertText(_ text: String) {
		CParsec.sendVirtualKeyboardInput(text: text) { [weak self] in self?.clearToolbarModifiers(sendToHost: true) }
	}

	func deleteBackward() {
		CParsec.sendVirtualKeyboardInput(text: "BACKSPACE") { [weak self] in self?.clearToolbarModifiers(sendToHost: true) }
	}

	// Mac order: esc and the modifiers, the function row, then the arrows and delete
	private func makeKeyGroups() -> [[KeyboardButton]] {
		let key = createKeyboardButton
		func combo(_ label: String, _ keys: [UInt32]) -> KeyboardButton {
			let button = key(label, "", false)
			button.combo = keys
			return button
		}
		return [
			[key("esc", "UIKeyInputEscape", false), key("⌃", "CONTROL", true), key("⌥", "LALT", true),
			 key("⌘", "LGUI", true), key("⇧", "SHIFT", true), key("⇥", "TAB", false)],
			(1...12).map { key("F\($0)", "F\($0)", false) },
			[key("←", "LEFT", false), key("↓", "DOWN", false), key("↑", "UP", false), key("→", "RIGHT", false),
			 key("⌦", "DELETE", false)],
			[combo("⌘C", [HIDKey.primary, HIDKey.c]), combo("⌘V", [HIDKey.primary, HIDKey.v]), combo("⌘X", [HIDKey.primary, HIDKey.x]),
			 combo("⌘Z", [HIDKey.primary, HIDKey.z]), combo("⌘A", [HIDKey.primary, HIDKey.a]),
			 combo("⌘⇥", [HIDKey.gui, HIDKey.tab]), combo("⌘␣", [HIDKey.gui, HIDKey.space]), combo("⌘H", [HIDKey.gui, HIDKey.h]),
			 combo("⌘⇧3", [HIDKey.gui, HIDKey.shift, HIDKey.three]), combo("⌘⇧4", [HIDKey.gui, HIDKey.shift, HIDKey.four])],
		]
	}

	// Half open, the system keeps anything above the keyboard on the upper half, so the key row would sit
	// on the picture. The keyboard's own shortcut bar is the one spot on the lower half: the keys go there
	// when this iPhone shows that bar, and back above the keyboard when it does not.
	func configureKeyPlacement() {
		let folded = halfFold() != nil
		// a later fold gets a fresh look, the bar may show this time
		if !folded { shortcutBarShown = nil }
		let inBar = keyboardVisible && folded && shortcutBarShown != false
		guard inBar != keysInShortcutBar else { return }
		// let go of a latched modifier before its key goes away
		clearToolbarModifiers(sendToHost: true)
		keysInShortcutBar = inBar
		shortcutBarKeys = []
		let item = inputAssistantItem
		guard inBar else {
			item.leadingBarButtonGroups = []
			item.trailingBarButtonGroups = []
			return
		}
		let groups = makeKeyGroups()
		shortcutBarKeys = groups.flatMap { $0 }
		func group(_ keys: [KeyboardButton], collapsed title: String? = nil) -> UIBarButtonItemGroup {
			let items = keys.map { UIBarButtonItem(customView: $0) }
			// when space runs out the system folds a group into this one key and pops the rest up
			return UIBarButtonItemGroup(barButtonItems: items, representativeItem: title.map { UIBarButtonItem(title: $0, style: .plain, target: nil, action: nil) })
		}
		let done = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain, target: self, action: #selector(doneTapped))
		item.leadingBarButtonGroups = [group(groups[0])]
		item.trailingBarButtonGroups = [group(groups[1], collapsed: "fn"), group(groups[2], collapsed: "←→"), group(groups[3], collapsed: "⌘"),
										UIBarButtonItemGroup(barButtonItems: [done], representativeItem: nil)]
	}

	// a key in the shortcut bar that never reaches a window means this iPhone draws no such bar
	func checkShortcutBar() {
		guard keysInShortcutBar else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			guard let self, self.keysInShortcutBar, self.isFirstResponder else { return }
			let shown = self.shortcutBarKeys.contains { $0.window != nil }
			guard !shown else { self.shortcutBarShown = true; return }
			self.shortcutBarShown = false
			self.configureKeyPlacement()
			self.reloadInputViews()
		}
	}

    // copied from moonlight https://github.com/moonlight-stream/moonlight-ios/blob/022352c1667788d8626b659d984a290aa5c25e17/Limelight/Input/StreamView.m#L393
	override var inputAccessoryView: UIView? {
		// a hardware keyboard alone gets no key row; the keyboard button brings it up
		if !keyboardVisible || keysInShortcutBar { return nil }
		if let keyboardAccessoriesView {
			return keyboardAccessoriesView
		}
        // Refactored to UIView with autoresizing mask for better landscape support
        // Using frame-based layout for the container to avoid constraint conflicts with keyboard
		let containerView = AccessoryContainerView(frame: CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 94))
        containerView.autoresizingMask = [.flexibleWidth]
        containerView.backgroundColor = .clear
		containerView.overrideUserInterfaceStyle = .dark

		// Use a simple UIView instead of UIToolbar to avoid constraint conflicts
		let toolbarBackground = UIView(frame: CGRect(x: 0, y: 50, width: containerView.bounds.width, height: 44))
		toolbarBackground.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
		toolbarBackground.backgroundColor = UIColor(white: 0.07, alpha: 0.96)
		let hairline = UIView(frame: CGRect(x: 0, y: 0, width: toolbarBackground.bounds.width, height: 0.5))
		hairline.autoresizingMask = [.flexibleWidth]
		hairline.backgroundColor = UIColor(white: 1, alpha: 0.1)
		toolbarBackground.addSubview(hairline)

		let scrollView = UIScrollView(frame: CGRect(x: 8, y: 0, width: toolbarBackground.bounds.width - 80, height: 44))
		scrollView.autoresizingMask = [.flexibleWidth]
		scrollView.showsHorizontalScrollIndicator = false

		// keys sit close within a group, with a wider gap between groups, like a Mac keyboard's clusters
		let buttonStackView = UIStackView(arrangedSubviews: makeKeyGroups().map { keys in
			let group = UIStackView(arrangedSubviews: keys)
			group.spacing = 6
			return group
		})
		buttonStackView.axis = .horizontal
		buttonStackView.alignment = .center
		buttonStackView.spacing = 16
		buttonStackView.translatesAutoresizingMaskIntoConstraints = false

		scrollView.addSubview(buttonStackView)

		// Set constraints for the stack view inside the scroll view
		NSLayoutConstraint.activate([
			buttonStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			buttonStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			buttonStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			buttonStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			buttonStackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
		])

		// Done button with frame-based layout
		let doneButton = UIButton(type: .system)
		doneButton.frame = CGRect(x: toolbarBackground.bounds.width - 70, y: 0, width: 60, height: 44)
		doneButton.autoresizingMask = [.flexibleLeftMargin]
		doneButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
		doneButton.tintColor = .white
		doneButton.accessibilityLabel = String(localized: "Done")
		doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

		let handle = UIImageView(image: UIImage(systemName: "arrow.up.and.down"))
		handle.frame = CGRect(x: 4, y: 0, width: 40, height: 44)
		handle.contentMode = .center
		handle.tintColor = .white
		handle.isUserInteractionEnabled = true
		handle.isHidden = true
		handle.isAccessibilityElement = true
		handle.accessibilityLabel = String(localized: "Move screen up or down")
		handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanHandle(_:))))
		let handleDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handlePanHandleDoubleTap(_:)))
		handleDoubleTap.numberOfTapsRequired = 2
		handle.addGestureRecognizer(handleDoubleTap)
		panHandle = handle
		keyScrollView = scrollView
		keyBarDone = doneButton
		containerView.onLayout = { [weak self] in self?.layoutKeyBar() }

		toolbarBackground.addSubview(scrollView)
		toolbarBackground.addSubview(handle)
		toolbarBackground.addSubview(doneButton)

		containerView.addSubview(toolbarBackground)

		keyboardAccessoriesView = containerView
		return containerView
	}

	func createKeyboardButton(displayText: String, keyText: String, isToggleable: Bool) -> KeyboardButton {
		let button = KeyboardButton(keyText: keyText, isToggleable: isToggleable)
		button.setTitle(displayText, for: .normal)
		// symbols read larger than words at the same size
		button.titleLabel?.font = displayText.count == 1 ? .systemFont(ofSize: 17, weight: .medium) : .systemFont(ofSize: 14, weight: .medium)
		button.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: displayText.count > 2 ? 46 : 40),
			button.heightAnchor.constraint(equalToConstant: 34),
		])
		button.addTarget(self, action: #selector(toolbarButtonClicked(_:)), for: .touchUpInside)
		return button
	}

	@objc private func inputWasReleased() {
		clearToolbarModifiers(sendToHost: false)
	}

	private func clearToolbarModifiers(sendToHost: Bool) {
		let keys = (keyboardAccessoriesView.map { toolbarButtons(in: $0) } ?? []) + shortcutBarKeys
		for button in keys where button.isOn {
			button.isOn = false
			if sendToHost {
				CParsec.sendVirtualKeyboardInput(text: button.keyText, isOn: false)
			}
		}
	}

	private func toolbarButtons(in view: UIView) -> [KeyboardButton] {
		let own = (view as? KeyboardButton).map { [$0] } ?? []
		return own + view.subviews.flatMap { toolbarButtons(in: $0) }
	}

	@objc func toolbarButtonClicked(_ sender: KeyboardButton) {
		if !sender.combo.isEmpty {
			// a combo carries its own modifiers; a latched one on top would make ⌘C something else
			clearToolbarModifiers(sendToHost: true)
			let keys = hostKeys(sender.combo, hostOS: DataManager.model.hostOS)
			for key in keys { CParsec.sendKeyboardMessage(keyCode: key, pressed: true) }
			for key in keys.reversed() { CParsec.sendKeyboardMessage(keyCode: key, pressed: false) }
			return
		}
		let isToggleable = sender.isToggleable
		var isOn = sender.isOn

		if isToggleable {
			isOn.toggle()
		}

		sender.isOn = isOn
		let keyText = sender.keyText

		if isToggleable {
			if isOn {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: true)
			} else {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: false)
			}
		} else {
			CParsec.sendVirtualKeyboardInput(text: keyText) { [weak self] in self?.clearToolbarModifiers(sendToHost: true) }
		}

	}

	@objc func doneTapped() {
		setKeyboardVisible(false)
	}

	// CRITICAL: This is the robust way to show the keyboard.
    // 1. Dispatch async to ensure view is attached to window.
    // 2. call reloadInputViews() to ensure updated accessory view (especially for rotation).
    // 3. call becomeFirstResponder().
    // 4. Do NOT simplify this to a synchronous call, or it will fail in some race conditions.
	func setKeyboardVisible(_ visible: Bool) {
		if visible {
			keyboardVisible = true
            DispatchQueue.main.async {
                // hidden again before this ran: raising it now would leave a keyboard nobody tracks
                guard self.keyboardVisible else { return }
                self.configureKeyPlacement()
                self.reloadInputViews()
                let success = self.becomeFirstResponder()
                // already first responder for a hardware keyboard, the key row may come up without a show notification
                if GCKeyboard.coalesced != nil { self.onKeyboardVisibilityChanged?(true) }
                if !success {
                   // Fallback: try again? or just log (can't log).
                   // Maybe ensure user interaction is on on window?
                }
            }
		} else {
			// keyboardVisible stays set so keyboardWillHide undoes the lift and tells SwiftUI; clearing it
			// first made the handler bail. Called again for when no notification comes (hardware keyboard),
			// a no-op once it ran
			resignFirstResponder()
			keyboardWillHide(notification: NSNotification(name: UIResponder.keyboardWillHideNotification, object: nil))
			// a hardware keyboard keeps typing once the key row is gone
			if GCKeyboard.coalesced != nil {
				DispatchQueue.main.async { self.hardwareKeyboardChanged() }
			}
		}
	}

}

protocol ParsecTouchInputDelegate: AnyObject {
	// Called on every touch change with the authoritative set of currently-active touches.
	func parsecTouchesUpdated(_ activeTouches: Set<UITouch>, moved: Bool)
}

// A transparent overlay that owns every raw touch and forwards it to the controller. Sitting on
// top of (not inside) the scroll view, it gives deterministic, unfiltered touch delivery with no
// UIScrollView gesture races - the controller decides 1-finger cursor vs 2-finger pinch / scroll.
class TouchOverlayView: UIView {
	weak var inputDelegate: ParsecTouchInputDelegate?

	// Forward the live touch set (excluding ended/cancelled) on every event. External mouse /
	// trackpad input arrives as indirect-pointer touches but is handled entirely by GCMouse, so it's
	// dropped here — otherwise it warps the direct-mode cursor and fights touchpad-mode drags.
	private func forward(_ event: UIEvent?, moved: Bool) {
		let active = (event?.allTouches ?? []).filter { touch in
			guard touch.phase != .ended && touch.phase != .cancelled else { return false }
			// the trackpad below the picture runs its own gestures
			if touch.view is TrackpadView { return false }
			if #available(iOS 13.4, *), touch.type == .indirectPointer { return false }
			return true
		}
		inputDelegate?.parsecTouchesUpdated(active, moved: moved)
	}
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: true) }
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
}

final class AccessoryContainerView: UIView {
	var onLayout: (() -> Void)?

	override func layoutSubviews() {
		super.layoutSubviews()
		onLayout?()
	}

	override func safeAreaInsetsDidChange() {
		super.safeAreaInsetsDidChange()
		setNeedsLayout()
	}

	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		subviews.contains { $0.frame.contains(point) }
	}
}

// MARK: - Trackpad below the picture

extension ParsecViewController: TrackpadDelegate {
	func trackpadMove(by delta: CGPoint) {
		guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
		let zoom = scrollView.zoomScale
		let s = CGFloat(mouseSensitivity) / zoom
		if CParsec.mouseInfo.mousePositionRelative {
			// the host captured the pointer (a game): true relative motion
			CParsec.sendMouseDelta(hostInt(delta.x * CGFloat(mouseSensitivity)), hostInt(delta.y * CGFloat(mouseSensitivity)))
			return
		}
		let dcx = delta.x * s, dcy = delta.y * s
		cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + dcx, y: cursorContentPos.y + dcy))
		let now = CACurrentMediaTime()
		let dt = CGFloat(now - lastCursorMoveTime)
		if dt > 0.0005 && dt < 0.1 {
			cursorVelocity = CGPoint(x: cursorVelocity.x * 0.4 + (dcx / dt) * 0.6, y: cursorVelocity.y * 0.4 + (dcy / dt) * 0.6)
		}
		lastCursorMoveTime = now
		CParsec.sendMousePosition(hostInt(cursorContentPos.x), hostInt(cursorContentPos.y))
		centerViewportOnCursorPos()
		positionCursorOverlay()
	}

	// what the host does for a gesture, named the way that host names it
	static func gestureTitle(_ gesture: TrackpadGesture, mac: Bool) -> (text: String, symbol: String) {
		switch gesture {
		case .swipeUp: return (mac ? String(localized: "Mission Control") : String(localized: "Task View"), "rectangle.3.group")
		case .swipeDown: return (mac ? String(localized: "App Exposé") : String(localized: "Show Desktop"), mac ? "rectangle.stack" : "menubar.dock.rectangle")
		case .swipeLeft: return (mac ? String(localized: "Next Space") : String(localized: "Next Desktop"), "arrow.right.square")
		case .swipeRight: return (mac ? String(localized: "Previous Space") : String(localized: "Previous Desktop"), "arrow.left.square")
		case .spread: return (String(localized: "Show Desktop"), "menubar.dock.rectangle")
		case .pinch: return (mac ? String(localized: "Spotlight") : String(localized: "Start"), mac ? "magnifyingglass" : "square.grid.2x2")
		}
	}

	func trackpadTouchBegan() {
		// a new touch stops a glide, so a tap lands where the cursor is now
		stopMomentum()
	}

	func trackpadCursorActive(_ active: Bool) {
		trackpadOwnsCursor = active
	}

	func trackpadMoveEnded() {
		startCursorMomentum(fromTrackpad: true)
	}

	func trackpadButton(_ button: Int32, pressed: Bool) {
		// a release always goes out so nothing sticks; a press only while streaming
		guard !pressed || ParsecBackgroundManager.shared.hasActiveConnection else { return }
		CParsec.sendMouseClickMessage(ParsecMouseButton(rawValue: UInt32(button)), pressed)
	}

	func trackpadTap(_ tap: TrackpadTap) {
		switch tap {
		case .leftClick, .rightClick:
			guard UIApplication.shared.applicationState == .active, ParsecBackgroundManager.shared.hasActiveConnection else { return }
			let button = ParsecMouseButton(rawValue: tap == .leftClick ? 1 : 3)
			CParsec.sendMouseClickMessage(button, true)
			CParsec.sendMouseClickMessage(button, false)
		case .toggleKeyboard:
			setKeyboardVisible(!keyboardVisible)
		}
	}

	func trackpadScroll(by delta: CGPoint) {
		guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
		stopMomentum()
		scrollWheel(byFingers: delta)
	}

	func trackpadScrollEnded() {
		startScrollMomentum()
	}

	// pinching the pad zooms the picture above, around the cursor
	func trackpadZoom(by scale: CGFloat) {
		guard zoomEnabled else { return }
		let off = scrollView.contentOffset
		let anchor = CGPoint(x: cursorContentPos.x * scrollView.zoomScale - off.x, y: cursorContentPos.y * scrollView.zoomScale - off.y)
		applyZoom(to: scrollView.zoomScale * scale, anchorInView: anchor)
	}

	func trackpadGesture(_ gesture: TrackpadGesture) {
		guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
		let hostOS = DataManager.model.hostOS
		let title = Self.gestureTitle(gesture, mac: hostOS == macHostOS)
		trackpad.showHUD(title: title.text, symbol: title.symbol)
		let keys = trackpadKeys(gesture, hostOS: hostOS)
		diag("trackpad \(gesture) -> \(keys)")
		for key in keys { CParsec.sendKeyboardMessage(keyCode: key, pressed: true) }
		for key in keys.reversed() { CParsec.sendKeyboardMessage(keyCode: key, pressed: false) }
	}
}
