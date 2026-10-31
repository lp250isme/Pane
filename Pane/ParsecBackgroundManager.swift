import UIKit
import AVFoundation
import GLKit

protocol RenderLoop: AnyObject {
	var isPaused: Bool { get set }
}

extension GLKViewController: RenderLoop {}

class ParsecBackgroundManager {
	static let shared = ParsecBackgroundManager()

	private(set) var hasActiveConnection = false
	private(set) var lastPeerId: String? {
		didSet { UserDefaults.standard.set(lastPeerId, forKey: "lastConnectedPeerId") }
	}
	private(set) var resumeOnLaunch: Bool {
		get { UserDefaults.standard.bool(forKey: "resumeLastHost") }
		set { UserDefaults.standard.set(newValue, forKey: "resumeLastHost") }
	}
	var lastHostname: String? {
		didSet {
			UserDefaults.standard.set(lastHostname, forKey: "lastConnectedHostname")
			updateShortcut()
		}
	}
	private var didDisconnectDueToBackground = false
	private(set) var isReconnecting = false
	var reconnectAttempts = 0
	var reconnectStartTime = Date()
	// when the retries started, for reconnectBudget
	var lostAt: Date?
	var resumedAt: Date?
	var isPaused = false
	weak var glkViewController: RenderLoop?
	// with several windows open, only the one that started the stream drives pause / PiP / disconnect
	weak var streamScene: UIScene?

	func ownsStream(_ scene: UIScene?) -> Bool {
		return streamScene == nil || streamScene === scene
	}

	var keyWindowScene: UIWindowScene? {
		UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.windows.contains { $0.isKeyWindow } }
	}

	var onShouldReconnect: ((String) -> Void)?
	var onShortcutReconnect: (() -> Void)?
	var reconnectPending = false
	static let reconnectShortcut = "reconnect"
	var onShouldDisconnect: (() -> Void)?

	var isMarkedForReconnect: Bool {
		return didDisconnectDueToBackground || isReconnecting
	}

	var isPiPActive: Bool {
		if #available(iOS 15.0, *) {
			return PictureInPictureManager.shared.isPiPActive
		}
		return false
	}

	private init() {
		lastPeerId = UserDefaults.standard.string(forKey: "lastConnectedPeerId")
		lastHostname = UserDefaults.standard.string(forKey: "lastConnectedHostname")
	}

	func updateShortcut() {
		UIApplication.shared.shortcutItems = lastHostname.map { [UIApplicationShortcutItem(type: Self.reconnectShortcut, localizedTitle: "Reconnect to \($0)", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "arrow.clockwise"), userInfo: nil)] }
	}

	func connectionDidStart() {
		hasActiveConnection = true
		didDisconnectDueToBackground = false
		isReconnecting = false
		isPaused = false
	}

	func connectionDidGoLive(peerId: String, hostname: String) {
		lastPeerId = peerId
		lastHostname = hostname
		resumeOnLaunch = true
	}

	func connectionDidEnd() {
		hasActiveConnection = false
		isPaused = false
		releaseHold()
	}

	private var hold: UIBackgroundTaskIdentifier = .invalid

	// keep the app running with the stream paused, so a quick trip to another app comes back to a live stream.
	// Once iOS calls time, end it cleanly (the host frees the seat) and reconnect on return
	func holdPausedStream() {
		guard hold == .invalid else { return }
		hold = UIApplication.shared.beginBackgroundTask(withName: "paused stream") { [weak self] in
			guard let self = self else { return }
			if self.hasActiveConnection && self.isPaused {
				appNote("[background] out of background time, disconnecting, reconnect on return")
				self.markForReconnect()
				self.onShouldDisconnect?()
			}
			self.releaseHold()
		}
	}

	func releaseHold() {
		guard hold != .invalid else { return }
		UIApplication.shared.endBackgroundTask(hold)
		hold = .invalid
	}

	func sceneWillResignActive() {
	}

	func sceneDidBecomeActive() {
		// Takes priority over isPiPActive check because stopPiP() is async
		if didDisconnectDueToBackground, let peerId = lastPeerId {
			didDisconnectDueToBackground = false
			isReconnecting = true

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.onShouldReconnect?(peerId)
			}
		}
	}

	func sceneDidEnterBackground() {
		if hasActiveConnection && !isPaused {
			var pipAttempted = false
			if #available(iOS 15.0, *) {
				pipAttempted = isPiPActive || PictureInPictureManager.shared.isStarting
			}
			if !pipAttempted {
				didDisconnectDueToBackground = true
			}
		}
	}

	func markForReconnect() {
		guard lastPeerId != nil else { return }
		didDisconnectDueToBackground = true
	}

	func endSession() {
		didDisconnectDueToBackground = false
		isReconnecting = false
		reconnectAttempts = 0
		lostAt = nil
		resumeOnLaunch = false
	}

	func disableAutoReconnect() {
		endSession()
		lastPeerId = nil
		lastHostname = nil
	}
}
