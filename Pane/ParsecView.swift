import SwiftUI
import ParsecSDK
import Foundation
import AVFoundation

struct ParsecStatusBar: View {
	@Binding var showMenu: Bool
	@State var metricInfo: String = "Loading..."
	@Binding var showDCAlert: Bool
	// an alert waiting for the menu popover to go, polling stays parked until it is raised
	@Binding var pendingDCAlert: Bool
	@Binding var DCAlertText: String
	@Binding var isReconnecting: Bool
	@Binding var connectionLost: Bool
	@State var networkFailureSince: Date?
	@State var lastSampleAt = Date.distantPast
	@State var lastRTx: UInt32 = 0
	@State var parsecViewController: ParsecViewController?
	@State var wasDisconnected: Bool = true
	let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
	let onSilentDisconnect: () -> Void

	init(showMenu: Binding<Bool>, showDCAlert: Binding<Bool>, pendingDCAlert: Binding<Bool>, DCAlertText: Binding<String>, parsecViewController: ParsecViewController, isReconnecting: Binding<Bool>, connectionLost: Binding<Bool>, onSilentDisconnect: @escaping () -> Void) {
		_showMenu = showMenu
		_showDCAlert = showDCAlert
		_pendingDCAlert = pendingDCAlert
		_DCAlertText = DCAlertText
		_isReconnecting = isReconnecting
		_connectionLost = connectionLost
		self.parsecViewController = parsecViewController
		self.onSilentDisconnect = onSilentDisconnect
	}

	var body: some View {
		// Overlay elements
		if showMenu || SettingsHandler.alwaysShowStatus {
			// a read-only status pill, the caller pads it inside the safe area
			Text(metricInfo)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.primary)
				.multilineTextAlignment(.center)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.streamChrome(Capsule(), material: .ultraThinMaterial)
				.accessibilityLabel("Stream stats")
				.accessibilityValue(metricInfo)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
				.allowsHitTesting(false)
				.zIndex(1)
		}
		EmptyView()
			.onReceive(timer) { _ in
				poll()
			}
	}

	func poll() {
		if showDCAlert || pendingDCAlert || ParsecBackgroundManager.shared.isPaused {
			return
		}

		var pcs = ParsecClientStatus()
		var status = CParsec.getStatusEx(&pcs)

		var pipActive = false
		if #available(iOS 15.0, *) {
			pipActive = PictureInPictureManager.shared.isPiPActive
		}

		if status == PARSEC_OK && pcs.networkFailure && !isReconnecting && !pipActive {
			if networkFailureSince == nil { networkFailureSince = Date() }
			let lost = Date().timeIntervalSince(networkFailureSince!)
			let justResumed = Date().timeIntervalSince(ParsecBackgroundManager.shared.resumedAt ?? .distantPast) < 10
			// the network moved or dropped: the old path won't come back, skip the wait
			let netMoved = Date().timeIntervalSince(NetworkWatcher.shared.changedAt ?? .distantPast) < 10 || NetworkWatcher.shared.noNetwork
			if !connectionLost { diag("[net] failure started") }
			connectionLost = true
			if lost >= 3 || justResumed || netMoved {
				networkFailureSince = nil
				connectionLost = false
				ParsecBackgroundManager.shared.resumedAt = nil
				status = NETWORK_ERR_INTERRUPTED
				appNote("[stream] network failure \(netMoved ? "after a network change" : "held"), treating it as a lost connection")
			}
		} else {
			if let since = networkFailureSince, status == PARSEC_OK, !pcs.networkFailure {
				diag("[net] failure cleared after \(String(format: "%.1f", Date().timeIntervalSince(since)))s")
			}
			networkFailureSince = nil
			connectionLost = false
		}

		if status != PARSEC_OK {
			if ParsecBackgroundManager.shared.isMarkedForReconnect {
				return
			}

			// a network that came back or moved since this try started makes the try stale
			let netBack = (NetworkWatcher.shared.changedAt ?? .distantPast) > ParsecBackgroundManager.shared.reconnectStartTime
			if status == PARSEC_CONNECTING && isReconnecting && !netBack {
				if Date().timeIntervalSince(ParsecBackgroundManager.shared.reconnectStartTime) < 15 {
					return
				}
			}

			if status == CONNECT_WRN_APPROVAL && isReconnecting {
				if Date().timeIntervalSince(ParsecBackgroundManager.shared.reconnectStartTime) < 60 {
					return
				}
			}

			// PiP: connection died (screen lock killed GPU). Kill connection+audio once,
			// subsequent polls exit via isMarkedForReconnect above.
			if pipActive {
				appNote("[stream] lost during picture in picture, status \(status.rawValue), reconnect owed")
				CParsec.disconnect()
				try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
				ParsecBackgroundManager.shared.connectionDidEnd()
				ParsecBackgroundManager.shared.markForReconnect()
				wasDisconnected = true
				return
			}

			if SettingsHandler.autoReconnect, !status.isPermanentFailure, let peerId = ParsecBackgroundManager.shared.lastPeerId {
				let mgr = ParsecBackgroundManager.shared
				let offline = NetworkWatcher.shared.noNetwork
				// the budget runs from when there's a network: an elevator or a tunnel waits as long as it takes
				if mgr.lostAt == nil || offline { mgr.lostAt = Date() }
				if Date().timeIntervalSince(mgr.lostAt!) < reconnectBudget {
					// no network: a try is bound to fail, wait for it to come back
					if offline && isReconnecting { return }
					if !netBack && Date().timeIntervalSince(mgr.reconnectStartTime) < reconnectGap(attempt: mgr.reconnectAttempts) {
						return
					}
					if !offline { mgr.reconnectAttempts += 1 }
					appNote("[reconnect] attempt \(mgr.reconnectAttempts) after status \(status.rawValue)\(offline ? ", no network" : netBack ? ", network changed" : "")")
					isReconnecting = true
					mgr.reconnectStartTime = Date()
					parsecViewController?.resetKeyState()
					CParsec.reconnect(peerId)
					return
				}
				mgr.reconnectAttempts = 0
				mgr.lostAt = nil
			}

			isReconnecting = false
			wasDisconnected = true
			let silent = SettingsHandler.autoReconnect && !SettingsHandler.errorPrompts && !status.isPermanentFailure
			appNote("[stream] ended, status \(status.rawValue), \(silent ? "silent" : "alert")")
			if silent {
				// silent: auto-reconnect spent its retries, dont nag with an alert
				onSilentDisconnect()
			} else {
				DCAlertText = status.readable()
				showDCAlert = true
			}
			return
		}

		if isReconnecting {
			ParsecBackgroundManager.shared.reconnectAttempts = 0
			ParsecBackgroundManager.shared.lostAt = nil
			isReconnecting = false
			appNote("[reconnect] live again")
			ParsecView.getHostUserData()
			var pumping = false
			if #available(iOS 15.0, *) { pumping = PictureInPictureManager.shared.isPumping }
			if !pumping {
				ParsecBackgroundManager.shared.glkViewController?.isPaused = false
			}
			// SDK forgets stream dims on reconnect, re-send them so the frame fills not corners
			if let vc = parsecViewController {
				CParsec.setFrame(vc.scrollView.bounds.width, vc.scrollView.bounds.height, vc.glkView.renderView.contentScaleFactor)
			}
		}

		// a line every 15 s in diagnostics.log, so a stutter report comes with numbers
		if Date().timeIntervalSince(lastSampleAt) >= 15 {
			let m = pcs.`self`.metrics.0
			let rtx = m.fastRTs + m.slowRTs
			// the counters start over on a reconnect
			diag("[net] rtt \(Int(m.networkLatency))ms, rtx +\(rtx >= lastRTx ? rtx - lastRTx : rtx), \(String(format: "%.1f", m.bitrate))Mbps, queue \(m.queuedFrames), decode \(String(format: "%.1f", m.decodeLatency))ms")
			lastSampleAt = Date()
			lastRTx = rtx
		}

		if showMenu || SettingsHandler.alwaysShowStatus {
			let str = String.fromBuffer(&pcs.decoder.0.name.0, length: 16)
			metricInfo = "Decode \(String(format: "%.2f", pcs.`self`.metrics.0.decodeLatency))ms    Encode \(String(format: "%.2f", pcs.`self`.metrics.0.encodeLatency))ms    Network \(String(format: "%.2f", pcs.`self`.metrics.0.networkLatency))ms    Bitrate \(String(format: "%.2f", pcs.`self`.metrics.0.bitrate))Mbps    RTx \(pcs.`self`.metrics.0.fastRTs + pcs.`self`.metrics.0.slowRTs)    Queue \(pcs.`self`.metrics.0.queuedFrames)    Draw \(String(format: "%.0f", CParsec.drawRate))fps \(CParsec.rendererName)    \(pcs.decoder.0.h265 ? "H265" : "H264") \(pcs.decoder.0.width)x\(pcs.decoder.0.height) \(pcs.decoder.0.color444 ? "4:4:4" : "4:2:0") \(str)"
		}
	}


}

// CRITICAL: This class exists to PERSIST the ParsecViewController instance across SwiftUI view updates.
// Do not remove or change to a struct. If ParsecViewController is recreated, the keyboard responder chain breaks.
class ParsecSession: ObservableObject {
    let controller: ParsecViewController

    init() {
        self.controller = ParsecViewController()
    }
}

struct ParsecView: View {
	var controller: ContentView?

	@State var showDCAlert: Bool = false
	// an alert that arrived while the menu popover was up, raised once the popover has gone
	@State var pendingDCAlert: Bool = false
	@State var DCAlertText: String = String(localized: "Disconnected (reason unknown)")
	@State var metricInfo: String = "Loading..."

	@State var hideOverlay: Bool = false
	// where the trackpad deck's toolbar sits (portrait, half fold); nil when the picture has the whole screen
	@State var deckToolbar: CGRect?
	@State var hideKeyboardButton: Bool = false
	@AppStorage("keyboardHintShown") var keyboardHintShown: Bool = false
	@AppStorage("keyboardPanHintShown") var keyboardPanHintShown: Bool = false
	@State var hint: String?
	// drives the stats line now that the menu is a popover (was showMenu)
	@State var showStats: Bool = false
	// the floating button opens the stream menu in a native popover
	@State var showMenuPopover: Bool = false
	// true from the panel's onAppear to its onDisappear, so it stays true while the popover animates out
	@State var menuPresented: Bool = false
	// measured height of the menu list so the popover fits its content (iOS 18+), an estimate before that
	@State var menuContentHeight: CGFloat = StreamChrome.menuHeightEstimate
	// which page of the stream menu is showing, back to the main one each time the popover opens
	@State var menuPage: MenuPage = .main
	// the bitrate picked from the stream menu this session, 0 for Host Default, nil while untouched
	// the popover can take first responder from the stream, remember to hand the keyboard back
	@State var keyboardUpBeforeMenu: Bool = false
	// actions that remove the popover's anchor (or the whole view) wait until it has gone
	@State var pendingMenuAction: PendingMenuAction?
	@State var streamEnded: Bool = false
	@AppStorage("menuSwipeHintShown") var menuSwipeHintShown: Bool = false

	enum PendingMenuAction {
		case hideButtons, disconnect
	}

	enum MenuPage {
		case main, resolution, bitrate, display
	}

	@State var showKeyboard: Bool = false
	@State var zoomEnabled: Bool = false

	@State var muted: Bool = false
	@State var preferH265: Bool = true
	@State var isReconnecting: Bool = false
	@State var connectionLost: Bool = false

	@State var bitrates: [Int]

    // Persist the VC across view updates using StateObject.
    // CRITICAL: Changing this to @State or a simple var will break the keyboard after menu interactions.
	@StateObject var session = ParsecSession()

    // Observer shared state for updates
    @ObservedObject var dataModel = DataManager.model
	@ObservedObject var settingsStore = SettingsStore.shared

    // Computed property for convenience refactoring
    var parsecViewController: ParsecViewController {
        return session.controller
    }

	// @State var showDisplays: Bool = false

	init(_ controller: ContentView?) {
		self.controller = controller

		_muted = State(initialValue: SettingsHandler.startMuted)
		_zoomEnabled = State(initialValue: SettingsHandler.zoomEnabled)
		_bitrates = State(initialValue: ParsecResolution.bitrates)

    }

    // We need to set up the callback somewhere safer than init.
    // 'onAppear' is a good place, or inside the init of ParsecSession if possible (but it doesn't have access to binding).
    // Let's use onAppear/post.

	var body: some View {
		// read the real safe area here, the stream layer itself runs edge to edge
		GeometryReader { proxy in
			streamLayer(safeArea: proxy.safeAreaInsets)
				.edgesIgnoringSafeArea(.all)
		}
		.statusBarHidden(SettingsHandler.hideStatusBar)
		.alert(isPresented: $showDCAlert) {
			Alert(title: Text(DCAlertText),
				  primaryButton: .default(Text("Reconnect"), action: {
					guard let peerId = ParsecBackgroundManager.shared.lastPeerId else {
						disconnect()
						return
					}
					showDCAlert = false
					isReconnecting = true
					ParsecBackgroundManager.shared.reconnectAttempts = 0
					ParsecBackgroundManager.shared.lostAt = nil
					ParsecBackgroundManager.shared.reconnectStartTime = Date()
					parsecViewController.resetKeyState()
					CParsec.reconnect(peerId)
				  }),
				  secondaryButton: .cancel(Text("Close"), action: {disconnect()}))
		}
		// an alert cant show while the popover is up: park it, close the popover, menuDidDismiss raises it.
		// polling stays gated on pendingDCAlert meanwhile, so nothing reconnects in the gap
		.onChange(of: showDCAlert) { shown in
			guard shown else { return }
			if menuPresented {
				pendingDCAlert = true
				showDCAlert = false
				showMenuPopover = false
			} else if showMenuPopover {
				// asked for but never on screen, nothing to wait for
				showMenuPopover = false
			}
		}
		.onChange(of: isReconnecting) { reconnecting in
			if !reconnecting {
				CParsec.setMuted(muted)
				if muted { CParsec.pause(video: false, audio: true) }
			}
		}
		.onAppear(perform: post)
		.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ParsecBackgroundDisconnect"))) { _ in
			if #available(iOS 15.0, *) {
				if PictureInPictureManager.shared.isPiPActive {
					return
				}
			}
			disconnect(isBackgroundDisconnect: true)
		}
	}

	func streamLayer(safeArea: EdgeInsets) -> some View {
		ZStack {

			UIViewControllerWrapper(self.parsecViewController)
				.zIndex(1)
				.prefersPersistentSystemOverlaysHidden()

			ParsecStatusBar(showMenu: $showStats, showDCAlert: $showDCAlert, pendingDCAlert: $pendingDCAlert, DCAlertText: $DCAlertText, parsecViewController: parsecViewController, isReconnecting: $isReconnecting, connectionLost: $connectionLost, onSilentDisconnect: { disconnect() })
				.padding(.top, safeArea.top + StreamChrome.spacing)
				.padding(.horizontal, statusSideInset(safeArea))
				.zIndex(1)

			if isReconnecting || connectionLost {
				PromptOverlay {
					ProgressView()
						.progressViewStyle(.circular)
						.controlSize(.large)
					Text(isReconnecting ? ParsecBackgroundManager.shared.lastHostname.map { "Reconnecting to \($0)..." } ?? "Reconnecting..." : "Connection lost...")
						.font(.headline)
						.multilineTextAlignment(.center)
					Button(role: .destructive, action: { disconnect() }) {
						Text("Disconnect")
							.frame(minWidth: 120)
					}
					.buttonStyle(.bordered)
					.controlSize(.large)
				}
				.zIndex(10)
			}

			if dataModel.isBlocked {
				Text("Host is using the machine")
					.font(.subheadline.weight(.medium))
					.padding(.horizontal, 20)
					.padding(.vertical, 12)
					.streamChrome(Capsule())
					.zIndex(3)
			}

			if let hint = hint {
				Text(hint)
					.font(.subheadline.weight(.medium))
					.multilineTextAlignment(.center)
					.padding(.horizontal, 22)
					.padding(.vertical, 12)
					.streamChrome(Capsule())
					// with the keyboard up the centre is covered, sit just below the top chrome instead
					.padding(.top, showKeyboard ? belowTopChrome(safeArea) : 0)
					.frame(maxHeight: .infinity, alignment: showKeyboard ? .top : .center)
					.allowsHitTesting(false)
					.zIndex(3)
			}

			// the keyboard covers the deck's bottom band, so its controls go back to floating over the picture
			if let bar = deckToolbar, !showKeyboard {
				deckToolbarView
					.frame(width: bar.width, height: bar.height)
					.position(x: bar.midX, y: bar.midY)
					.zIndex(2)
			}

			// with the trackpad deck the controls live in its toolbar and the picture stays clear
			if deckToolbar == nil || showKeyboard { VStack {
				if !hideOverlay {
					HStack {
						overlayMenuButton
							.padding(StreamChrome.edge)
							.edgesIgnoringSafeArea(.all)
						Spacer()
					}
				}
				if !hideKeyboardButton {
					HStack {
						keyboardButton
							.padding(.leading, StreamChrome.edge)
							// alone it takes the menu button's top inset instead of hugging the edge
							.padding(.top, hideOverlay ? StreamChrome.edge : 0)
						.edgesIgnoringSafeArea(.all)
						Spacer()
					}
				}
				Spacer()
			}
			.zIndex(2) }
		}
	}

	// the deck's toolbar: the stream menu, Mission Control, the desktop and the keyboard, Mac-dock style
	var deckToolbarView: some View {
		let mac = dataModel.hostOS == macHostOS
		return HStack(spacing: 16) {
			overlayMenuButton
			deckButton("rectangle.3.group", label: mac ? "Mission Control" : "Task View") {
				parsecViewController.trackpadGesture(.swipeUp)
			}
			deckButton("menubar.dock.rectangle", label: "Show Desktop") {
				parsecViewController.trackpadGesture(.spread)
			}
			if !hideKeyboardButton {
				keyboardButton
			}
		}
		.padding(.bottom, 6)
		// it always sits on the stream's black
		.environment(\.colorScheme, .dark)
	}

	@ViewBuilder
	func deckButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
		if #available(iOS 26, *) {
			Button(action: action) {
				Image(systemName: symbol)
					.font(.system(size: 20, weight: .medium))
					.frame(width: 32, height: 32)
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.foregroundStyle(.white)
			.accessibilityLabel(label)
		} else {
			Button(action: action) {
				Image(systemName: symbol)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 28, height: 28)
					.foregroundColor(.white)
					.padding(10)
					.background(Circle().fill(Color.white.opacity(0.14)))
			}
			.accessibilityLabel(label)
		}
	}

	// keep the stats pill centred and clear of the corner buttons and the sensor housing
	func statusSideInset(_ safeArea: EdgeInsets) -> CGFloat {
		let buttonsShown = !hideOverlay || !hideKeyboardButton
		let clearOfButtons = buttonsShown ? StreamChrome.edge + StreamChrome.buttonSize + StreamChrome.spacing : 0
		return max(max(safeArea.leading, safeArea.trailing) + StreamChrome.spacing, clearOfButtons)
	}

	// the first row under the menu button and the stats pill
	func belowTopChrome(_ safeArea: EdgeInsets) -> CGFloat {
		max(safeArea.top + StreamChrome.spacing, StreamChrome.edge) + StreamChrome.buttonSize + StreamChrome.spacing
	}

	var menuOpen: Bool { showMenuPopover || menuPresented }

	// the floating button is a plain Button (a Menu here never got the tap over the stream view),
	// it opens the stream menu in a native popover, iOS 26 gives the button Liquid Glass
	var overlayMenuButton: some View {
		styledMenuButton
			.accessibilityLabel("Menu")
			.popover(isPresented: $showMenuPopover) {
				overlayMenuPanel
			}
	}

	@ViewBuilder
	var styledMenuButton: some View {
		if #available(iOS 26, *) {
			// glass circle, dimmed while idle so it stays out of the picture
			Button(action: toggleMenu) {
				// the Parsec logo in its own colours, the glass would otherwise tint it like a symbol
				Image("IconTransparent")
					.renderingMode(.original)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 26, height: 26)
					.frame(width: 32, height: 32)
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			// dimmed while idle over the picture; on the deck it is a plain control
			.opacity(menuOpen || deckToolbar != nil ? 1 : 0.6)
			.animation(.easeOut(duration: 0.2), value: menuOpen)
		} else {
			Button(action: toggleMenu) {
				Image("IconTransparent")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 48, height: 48)
					.background(Rectangle().fill(Color("BackgroundPrompt").opacity(showMenuPopover ? 0.75 : 1)))
					.cornerRadius(8)
					.opacity(showMenuPopover ? 1 : 0.25)
			}
		}
	}

	@ViewBuilder
	var keyboardButton: some View {
		if #available(iOS 26, *) {
			let button = Button(action: toggleKeyboard) {
				Image(systemName: "keyboard")
					.font(.system(size: 20, weight: .medium))
					.frame(width: 32, height: 32)
			}
			.buttonBorderShape(.circle)
			.accessibilityLabel("Keyboard")
			.accessibilityAddTraits(showKeyboard ? .isSelected : [])

			// prominent glass marks the keyboard as up
			if showKeyboard {
				button.buttonStyle(.glassProminent).onAccentLabel()
			} else {
				// over the stream, which is mostly dark: the black-and-white accent would tint it black in light mode
				button.buttonStyle(.glass).foregroundStyle(.white)
			}
		} else {
			Button(action: toggleKeyboard) {
				Image(systemName: "keyboard")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 32, height: 32)
					.foregroundColor(Color("Foreground"))
					.padding(8)
					.background(Rectangle().fill(Color("BackgroundPrompt").opacity(showKeyboard ? 0.75 : 0.5)))
					.cornerRadius(8)
			}
			.accessibilityLabel("Keyboard")
		}
	}

	var overlayMenuPanel: some View {
		List {
			switch menuPage {
			case .main:
				overlayMenuContent
			case .resolution:
				resolutionPage
			case .bitrate:
				bitratePage
			case .display:
				displayPage
			}
		}
		.listStyle(.insetGrouped)
		.toggleStyle(SwitchToggleStyle(tint: .green))
		.popoverListBackground()
		.fitsContentHeight($menuContentHeight)
		// a fresh list and height reading per page, so it starts at the top and the popover fits that page
		.id(menuPage)
		.compactPopover(done: { showMenuPopover = false })
		// the popover clamps this to the space it has, so landscape scrolls instead of overflowing
		.frame(minWidth: 320, idealWidth: 340, idealHeight: menuContentHeight)
		.onAppear {
			menuPresented = true
			menuPage = .main
		}
		.onDisappear {
			menuPresented = false
			menuPage = .main
			menuDidDismiss()
		}
	}

	@ViewBuilder
	var overlayMenuContent: some View {
		Section {
			// a Mac host can't change its display mode (parsecd has no display-mode API), so the choice does nothing there
			if let os = dataModel.hostOS, os != macHostOS {
				MenuDrillRow("Resolution", systemImage: "aspectratio", value: resolutionSummary) {
					menuPage = .resolution
				}
			}

			MenuDrillRow("Bitrate", systemImage: "speedometer", value: bitrateSummary) {
				menuPage = .bitrate
			}

			if dataModel.displayConfigs.count > 1 {
				MenuDrillRow("Switch Display", systemImage: "display", value: displaySummary) {
					menuPage = .display
				}
			}
		}

		Section {
			Toggle(isOn: Binding(get: { !muted }, set: { _ in toggleMute() })) {
				Label("Sound", systemImage: "speaker.wave.2")
			}
			Toggle(isOn: Binding(get: { dataModel.constantFps }, set: { _ in toggleConstantFps() })) {
				Label("Constant Frame Rate", systemImage: "timer")
			}
			Toggle(isOn: Binding(get: { zoomEnabled }, set: { _ in toggleZoom() })) {
				Label("Pinch to Zoom", systemImage: "plus.magnifyingglass")
			}
			Toggle(isOn: Binding(get: { showStats || SettingsHandler.alwaysShowStatus }, set: { showStats = $0 })) {
				Label("Show Stats", systemImage: "chart.bar")
			}
			// the always show setting wins, the item just reflects it
			.disabled(SettingsHandler.alwaysShowStatus)
		}

		Section {
			Button(action: { closeMenu(then: .hideButtons) }) {
				Label("Hide Buttons", systemImage: "eye.slash")
			}
		}

		Section {
			Button(role: .destructive, action: { closeMenu(then: .disconnect) }) {
				Label("Disconnect", systemImage: "power")
			}
		}
	}

	@ViewBuilder
	var resolutionPage: some View {
		Section {
			MenuBackRow(title: "Resolution") { menuPage = .main }
		}
		Section {
			ForEach(ParsecResolution.resolutions, id: \.self) { res in
				MenuOptionRow(LocalizedStringKey(res.desc), checked: res == currentResolution) { changeResolution(res) }
			}
		}
	}

	var currentResolution: ParsecResolution? {
		ParsecResolution.resolutions.first { $0.width == dataModel.resolutionX && $0.height == dataModel.resolutionY }
	}

	var resolutionSummary: String { currentResolution.map { String(localized: String.LocalizationValue($0.desc)) } ?? "" }

	@ViewBuilder
	var bitratePage: some View {
		Section {
			MenuBackRow(title: "Bitrate") { menuPage = .main }
		}
		Section {
			MenuOptionRow("Host Default", checked: bitrateIsHostDefault) { changeStreamBitrate(0) }
				.disabled(dataModel.hostDefaultBitrate <= 0)
			ForEach(bitrates, id: \.self) { bitrate in
				MenuOptionRow("\(bitrate) Mbps", checked: !bitrateIsHostDefault && dataModel.bitrate == bitrate) { changeStreamBitrate(bitrate) }
			}
		}
	}

	@ViewBuilder
	var displayPage: some View {
		Section {
			MenuBackRow(title: "Switch Display") { menuPage = .main }
		}
		Section {
			MenuOptionRow("Auto", checked: dataModel.output == "none") { pickDisplay("none") }
			ForEach(dataModel.displayConfigs, id: \.self) { config in
				MenuOptionRow("\(config.name) \(config.adapterName)", checked: dataModel.output == config.id) { pickDisplay(config.id) }
			}
		}
	}

	// the host's live bitrate reads as Host Default while it matches, unless that exact number was picked
	var bitrateIsHostDefault: Bool {
		dataModel.hostDefaultBitrate > 0 && (dataModel.streamBitrate ?? SettingsHandler.bitrate) == 0 && dataModel.bitrate == dataModel.hostDefaultBitrate
	}

	var bitrateSummary: String {
		if bitrateIsHostDefault { return String(localized: "Host Default") }
		return dataModel.bitrate > 0 ? String(localized: "\(dataModel.bitrate) Mbps") : ""
	}

	var displaySummary: String {
		if dataModel.output == "none" { return String(localized: "Auto") }
		return dataModel.displayConfigs.first { $0.id == dataModel.output }.map { "\($0.name) \($0.adapterName)" } ?? ""
	}

	func pickDisplay(_ displayId: String) {
		menuPage = .main
		guard displayId != dataModel.output else { return }
		changeDisplay(displayId: displayId)
	}

	func toggleMenu() {
		if showMenuPopover {
			showMenuPopover = false
			return
		}
		// still animating out, let it go before opening again
		guard !menuPresented else { return }
		keyboardUpBeforeMenu = showKeyboard
		ParsecView.getHostUserData()
		showMenuPopover = true
	}

	func closeMenu(then action: PendingMenuAction) {
		pendingMenuAction = action
		showMenuPopover = false
	}

	// runs once the popover has gone: deferred actions first, then the keyboard goes back to the stream
	func menuDidDismiss() {
		// the stream is already being torn down, nothing left to restore
		guard !streamEnded else { return }
		let action = pendingMenuAction
		pendingMenuAction = nil
		let restoreKeyboard = keyboardUpBeforeMenu || showKeyboard
		keyboardUpBeforeMenu = false
		switch action {
		case .disconnect:
			disconnect()
			return
		case .hideButtons:
			disableOverlay()
		case nil:
			break
		}
		// an alert held back while the popover was up goes now, on the next turn so the popover has fully let go.
		// the keyboard stays down under it
		if pendingDCAlert {
			DispatchQueue.main.async {
				guard !streamEnded else { return }
				showDCAlert = true
				pendingDCAlert = false
			}
			return
		}
		guard restoreKeyboard else { return }
		parsecViewController.setKeyboardVisible(true)
	}

	func post() {
		ParsecBackgroundManager.shared.onShouldDisconnect = {
			NotificationCenter.default.post(name: NSNotification.Name("ParsecBackgroundDisconnect"), object: nil)
		}
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.onPiPStopped = { [self] in
				if UIApplication.shared.applicationState != .active {
					ParsecBackgroundManager.shared.glkViewController?.isPaused = true
					CParsec.sendReleaseMessage()
					CParsec.pause()
					ParsecBackgroundManager.shared.isPaused = true
					ParsecBackgroundManager.shared.holdPausedStream()
				} else {
					if ParsecBackgroundManager.shared.isReconnecting {
						return
					}
					// Check actual Parsec status — timers don't reliably fire in background
					var pcs = ParsecClientStatus()
					let currentStatus = CParsec.getStatusEx(&pcs)
					if currentStatus != PARSEC_OK || ParsecBackgroundManager.shared.isMarkedForReconnect {
						CParsec.disconnect()
						try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
						ParsecBackgroundManager.shared.markForReconnect()
						DispatchQueue.main.async {
							self.disconnect(isBackgroundDisconnect: true)
						}
					}
				}
			}
			PictureInPictureManager.shared.onPiPStartFailed = {
				if UIApplication.shared.applicationState != .active {
					ParsecBackgroundManager.shared.glkViewController?.isPaused = true
					CParsec.sendReleaseMessage()
					CParsec.pause()
					ParsecBackgroundManager.shared.isPaused = true
					ParsecBackgroundManager.shared.holdPausedStream()
				}
			}
		}

		CParsec.applyConfig()
		CParsec.setMuted(muted)
		if muted { CParsec.pause(video: false, audio: true) }
		parsecViewController.setZoomEnabled(zoomEnabled)

		DataManager.model.constantFps = SettingsHandler.constantFps

		let screenSize: CGSize = self.parsecViewController.view.frame.size
		let scaleFactor = self.parsecViewController.view.window?.windowScene?.screen.nativeScale ?? UIScreen.main.nativeScale
		ParsecResolution.updateClientResolution(width: Int(screenSize.width * scaleFactor), height: Int(screenSize.height * scaleFactor))

		ParsecView.getHostUserData()

		hideOverlay = SettingsHandler.noOverlay
		hideKeyboardButton = !SettingsHandler.showKeyboardButton
		parsecViewController.updateMenuEdgeSwipe(menuHidden: hideOverlay)
		offerHint()

		let overlayHidden = $hideOverlay
		let keyboardButtonHidden = $hideKeyboardButton
		let menuShown = $showMenuPopover
		let menuOnScreen = $menuPresented
		let ended = $streamEnded
		let keyboardUpBeforeMenu = $keyboardUpBeforeMenu
        let keyboardShown = $showKeyboard
		// the swipe brings the buttons back and opens the menu, like the old panel did
		parsecViewController.onMenuEdgeSwipe = {
			let wasHidden = overlayHidden.wrappedValue
			overlayHidden.wrappedValue = false
			keyboardButtonHidden.wrappedValue = !SettingsHandler.showKeyboardButton
			ParsecView.getHostUserData()
			// showMenuPopover is already false while the popover animates out, so also check it is off screen
			guard !menuShown.wrappedValue, !menuOnScreen.wrappedValue, !ended.wrappedValue else { return }
			keyboardUpBeforeMenu.wrappedValue = keyboardShown.wrappedValue
			// a button that just came back needs a layout pass before it can anchor the popover
			DispatchQueue.main.asyncAfter(deadline: .now() + (wasHidden ? 0.15 : 0)) {
				guard !menuOnScreen.wrappedValue, !ended.wrappedValue else { return }
				menuShown.wrappedValue = true
			}
		}

        parsecViewController.onKeyboardVisibilityChanged = { visible in
            keyboardShown.wrappedValue = visible
        }
		let deck = $deckToolbar
		parsecViewController.onDeckToolbarChanged = { deck.wrappedValue = $0 }
		// the first layout may have run before this was listening
		deckToolbar = parsecViewController.deckToolbarFrame
		let hint = $hint
		let panHintShown = $keyboardPanHintShown
		parsecViewController.onKeyboardCoversPicture = {
			guard !panHintShown.wrappedValue else { return }
			panHintShown.wrappedValue = true
			withAnimation { hint.wrappedValue = String(localized: "Part of the screen is under the keyboard\nDrag ↕\u{FE0E} to move it into view") }
			DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
				withAnimation { hint.wrappedValue = nil }
			}
		}

		parsecViewController.setKeyboardVisible(showKeyboard)
	}

	func disableOverlay() {
		hideOverlay = true
		hideKeyboardButton = true
		showStats = false
		parsecViewController.updateMenuEdgeSwipe(menuHidden: true)
		offerHint(always: true)
	}

	func offerHint(always: Bool = false) {
		// with the trackpad deck the menu button stays in its toolbar, nothing to bring back
		let menu = hideOverlay && deckToolbar == nil && (always || !menuSwipeHintShown)
		let keyboard = hideKeyboardButton && (always || !keyboardHintShown)
		guard menu || keyboard else { return }
		if menu { menuSwipeHintShown = true }
		if keyboard { keyboardHintShown = true }
		let text = [menu ? String(localized: "Swipe from the left edge to bring the menu back") : nil, keyboard ? String(localized: "Tap with three fingers to show or hide the keyboard") : nil].compactMap { $0 }.joined(separator: "\n")
		withAnimation { hint = text }
		DispatchQueue.main.asyncAfter(deadline: .now() + (menu && keyboard ? 6 : 4)) {
			withAnimation { hint = nil }
		}
	}

	func toggleMute() {
		muted.toggle()
		CParsec.setMuted(muted)
		if muted {
			CParsec.pause(video: false, audio: true)
		} else {
			CParsec.resume()
		}
	}

		/*func genDisplaySheet() -> ActionSheet
	{
		let len:Int = 16
		var outputs = [ParsecOutput?](repeating:nil, count:len)
		ParsecGetOutputs(&outputs, UInt32(len))
		print("Listing \(outputs.count) displays")

		func getDeviceName(_ output:ParsecOutput) -> String
		{
			return withUnsafePointer(to:output.device)
			{
				$0.withMemoryRebound(to: UInt8.self, capacity:MemoryLayout.size(ofValue:$0))
				{
					String(cString:$0)
				}
			}
		}

		let buttons = outputs.enumerated().map
		{ i, output in
			Alert.Button.default(Text("\(i) - \(getDeviceName(output))"), action:{print("Selected device \(i)")})
		}
		return ActionSheet(title: Text("Select a Display:"), buttons:buttons + [Alert.Button.cancel()])
	}*/

	func disconnect(isBackgroundDisconnect: Bool = false) {
		// popover Disconnect and a stream dying mid-dismiss can both land here, tear down once
		guard !streamEnded else { return }
		appNote("[stream] disconnect\(isBackgroundDisconnect ? " in the background" : "")")
		streamEnded = true
		pendingMenuAction = nil
		keyboardUpBeforeMenu = false
		pendingDCAlert = false
		showMenuPopover = false
		if !isBackgroundDisconnect {
			ParsecBackgroundManager.shared.endSession()
		}

		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.teardown()
		}

		CParsec.sendReleaseMessage()
		CParsec.disconnect()
		DataManager.model.output = "none"
		CParsec.drawRate = 0
		self.parsecViewController.glkView.cleanUp()

		parsecViewController.scrollView.zoomScale = 1.0
		parsecViewController.scrollView.contentOffset = .zero

		if let c = controller {
			c.setView(.main)
		}
	}

	func changeResolution(_ res: ParsecResolution) {
		menuPage = .main
		SettingsHandler.resolution = res
		DataManager.model.resolutionX = res.width
		DataManager.model.resolutionY = res.height
		DataManager.model.localChangeAt = Date()
		CParsec.updateHostVideoConfig()
	}

	// stream only, 0 goes back to the host's own bitrate. The saved default lives in Settings
	func changeStreamBitrate(_ bitrate: Int) {
		menuPage = .main
		DataManager.model.streamBitrate = bitrate
		let target = bitrate > 0 ? bitrate : DataManager.model.hostDefaultBitrate
		guard target > 0, target != DataManager.model.bitrate else { return }
		DataManager.model.bitrate = target
		DataManager.model.localChangeAt = Date()
		CParsec.updateHostVideoConfig()
	}

	func toggleConstantFps() {
		DispatchQueue.main.async {
			DataManager.model.constantFps.toggle()
			DataManager.model.localChangeAt = Date()
			CParsec.updateHostVideoConfig()
			SettingsHandler.constantFps = DataManager.model.constantFps
		}
	}

	func toggleKeyboard() {
		DispatchQueue.main.async {
			showKeyboard.toggle()
			parsecViewController.setKeyboardVisible(showKeyboard)
		}
	}

	func toggleZoom() {
		DispatchQueue.main.async {
			zoomEnabled.toggle()
			parsecViewController.setZoomEnabled(zoomEnabled)
			SettingsHandler.zoomEnabled = zoomEnabled
		}
	}

	func changeDisplay(displayId: String) {
		diag("pick display \(displayId)")
		DispatchQueue.main.async {
			DataManager.model.output = displayId
			DataManager.model.localChangeAt = Date()
			CParsec.updateHostVideoConfig()
		}
	}

	static func getHostUserData() {
		let data = Data()
		CParsec.sendUserData(type: .getVideoConfig, message: data)
		CParsec.sendUserData(type: .getAdapterInfo, message: data)
	}

}

// from https://github.com/utmapp/UTM/blob/117e3a962f2f46f7d847632d65fa7a85a2bb0cfa/Platform/iOS/VMWindowView.swift#L314
private extension View {
	func prefersPersistentSystemOverlaysHidden() -> some View {
		if #available(iOS 16, *) {
			return self.persistentSystemOverlays(.hidden)
		} else {
			return self
		}
	}

	// in-stream chrome sits on Liquid Glass on iOS 26, a system material before that
	@ViewBuilder
	func streamChrome<S: Shape>(_ shape: S, material: Material = .regularMaterial) -> some View {
		if #available(iOS 26, *) {
			self.glassEffect(.regular, in: shape)
		} else {
			self.background(material, in: shape)
		}
	}

	// keeps the menu an anchored bubble on iPhone, older systems fall back to a sheet that needs a way out
	@ViewBuilder
	func compactPopover(done: @escaping () -> Void) -> some View {
		if #available(iOS 16.4, *) {
			self.presentationCompactAdaptation(.popover)
		} else {
			NavigationView {
				self
					.navigationTitle("Menu")
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .confirmationAction) {
							Button("Done", action: done)
						}
					}
			}
			.navigationViewStyle(.stack)
		}
	}

	// on iOS 26 the popover is glass, let it show through the list
	@ViewBuilder
	func popoverListBackground() -> some View {
		if #available(iOS 26, *) {
			self.scrollContentBackground(.hidden)
		} else {
			self
		}
	}

	// reports the list's full content height so the popover can size to it
	@ViewBuilder
	func fitsContentHeight(_ height: Binding<CGFloat>) -> some View {
		if #available(iOS 18, *) {
			self.onScrollGeometryChange(for: CGFloat.self) { geometry in
				(geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom).rounded(.up)
			} action: { _, measured in
				if measured > 0, abs(measured - height.wrappedValue) > 1 {
					height.wrappedValue = measured
				}
			}
		} else {
			self
		}
	}
}

// spacing for the floating stream chrome, shared so the pieces line up with each other
private enum StreamChrome {
	// gap between the screen edge and the corner buttons
	static let edge: CGFloat = 16
	// footprint of a corner button, the glass circle on iOS 26 and the square below
	static let buttonSize: CGFloat = 48
	static let spacing: CGFloat = 8
	// popover height before the list has been measured, and for good below iOS 18
	static let menuHeightEstimate: CGFloat = 520
}

/// A stream menu row that opens a page of options, plain buttons only (menus never got the tap here)
private struct MenuDrillRow: View {
	let title: LocalizedStringKey
	let systemImage: String
	let value: String
	let action: () -> Void

	init(_ title: LocalizedStringKey, systemImage: String, value: String, action: @escaping () -> Void) {
		self.title = title
		self.systemImage = systemImage
		self.value = value
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			HStack(spacing: 8) {
				Label {
					Text(title).foregroundColor(.primary)
				} icon: {
					Image(systemName: systemImage)
				}
				Spacer(minLength: 8)
				Text(value)
					.foregroundColor(.secondary)
					.lineLimit(1)
				Image(systemName: "chevron.right")
					.font(.footnote.weight(.semibold))
					.foregroundColor(Color(.tertiaryLabel))
			}
			.contentShape(Rectangle())
		}
		.accessibilityValue(value)
	}
}

/// The way back from an options page to the main stream menu
private struct MenuBackRow: View {
	let title: LocalizedStringKey
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				Image(systemName: "chevron.left")
					.font(.body.weight(.semibold))
				Text(title)
					.font(.headline)
					.foregroundColor(.primary)
				Spacer()
			}
			.contentShape(Rectangle())
		}
		.accessibilityLabel("Back")
		.accessibilityHint(title)
	}
}

/// One choice on an options page, the current one carries a checkmark
private struct MenuOptionRow: View {
	let title: LocalizedStringKey
	let checked: Bool
	let action: () -> Void

	@Environment(\.isEnabled) private var isEnabled

	init(_ title: LocalizedStringKey, checked: Bool, action: @escaping () -> Void) {
		self.title = title
		self.checked = checked
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			HStack {
				Text(title)
					.foregroundColor(isEnabled ? .primary : .secondary)
				Spacer()
				if checked {
					Image(systemName: "checkmark")
						.font(.body.weight(.semibold))
						.foregroundColor(.accentColor)
				}
			}
			.contentShape(Rectangle())
		}
		.accessibilityAddTraits(checked ? .isSelected : [])
	}
}
