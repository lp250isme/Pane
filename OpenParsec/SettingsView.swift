import SwiftUI

/// The settings content as a native grouped Form. Used directly as the detail
/// page of the iOS 17+ sidebar, and wrapped by `SettingsView` on iOS 15/16.
///
/// Every row binds straight to `SettingsStore`, whose setters write to
/// UserDefaults immediately, so changes persist without any explicit save step.
struct SettingsForm: View {
	@ObservedObject private var settings = SettingsStore.shared

	private let resolutionChoices: [Choice<ParsecResolution>] =
		ParsecResolution.resolutions.map { Choice($0.desc, $0) }

	private let bitrateChoices: [Choice<Int>] =
		[Choice("Host Default", 0)] + ParsecResolution.bitrates.map { Choice("\($0) Mbps", $0) }

	var body: some View {
		Form {
			Section(header: Text("Touch & Mouse")) {
				MenuPickerRow("Touch Mode", selection: $settings.cursorMode, options: [
					Choice("Touchpad", CursorMode.touchpad),
					Choice("Direct", CursorMode.direct)
				])
				MenuPickerRow("Right Click", selection: $settings.rightClickPosition, options: [
					Choice("First Finger", RightClickPosition.firstFinger),
					Choice("Middle", RightClickPosition.middle),
					Choice("Second Finger", RightClickPosition.secondFinger)
				])
				ValueSliderRow("Pointer Speed", value: $settings.mouseSensitivity, in: 0.1...4, step: 0.1)
				ValueSliderRow("Cursor Size", value: $settings.cursorScale, in: 0.1...4, step: 0.1)
				ValueSliderRow("Scroll Speed", value: $settings.scrollSensitivity, in: 0.5...5, step: 0.5)
				Toggle("Reverse Scrolling", isOn: $settings.reverseScrollDirection)
				Toggle("Pinch to Zoom", isOn: $settings.zoomEnabled)
			}

			Section(header: Text("Keyboard")) {
				Toggle("Show Keyboard Button", isOn: $settings.showKeyboardButton)
				Toggle("Option Key as Command", isOn: $settings.optionAsCommand)
			}

			Section(header: Text("Video")) {
				MenuPickerRow("Renderer", selection: $settings.renderer, options: [
					Choice("OpenGL", RendererType.opengl),
					Choice("Metal", RendererType.metal)
				])
				MenuPickerRow("Resolution", selection: $settings.resolution, options: resolutionChoices)
				MenuPickerRow("Bitrate", selection: $settings.bitrate, options: bitrateChoices)
				MenuPickerRow("Frame Rate", selection: $settings.preferredFramesPerSecond, options: [
					Choice("Auto (Device Max)", 0),
					Choice("120 FPS", 120),
					Choice("60 FPS", 60),
					Choice("30 FPS", 30)
				])
				Toggle("Constant Frame Rate", isOn: $settings.constantFps)
				MenuPickerRow("Codec", selection: $settings.decoder, options: [
					Choice("H.264", DecoderPref.h264),
					Choice("Prefer H.265", DecoderPref.h265)
				])
			}

			Section(header: Text("During a Stream")) {
				Toggle("Show Stream Stats", isOn: $settings.alwaysShowStatus)
				Toggle("Show Menu Button", isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 }))
				MenuPickerRow("Menu Edge Swipe", selection: $settings.menuSwipeEdge, options: [
					Choice("Off", MenuSwipeEdge.off),
					Choice("Left Edge", MenuSwipeEdge.left),
					Choice("Right Edge", MenuSwipeEdge.right)
				])
				Toggle(UIDevice.current.userInterfaceIdiom == .pad ? "Hide iPad Status Bar" : "Hide iPhone Status Bar", isOn: $settings.hideStatusBar)
				Toggle("Picture in Picture", isOn: $settings.enablePiP)
				Toggle("Start Muted", isOn: $settings.startMuted)
			}

			Section {
				Toggle("Auto Reconnect", isOn: $settings.autoReconnect)
				if settings.autoReconnect {
					Toggle("Show Reconnect Errors", isOn: $settings.errorPrompts)
				}
			} header: {
				Text("Connection")
			} footer: {
				Text(Self.versionInfo)
			}
		}
		.navigationTitle("Settings")
		// SettingsView used to be the only place applying this; keep it here so the
		// iOS 17+ detail page gets the same scheme.
		.preferredColorScheme(appScheme)
	}

	static var versionInfo: String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown version"
		let commit = info?["GitCommitInfo"] as? String ?? "Unknown commit"
		return "Version \(version)-\(commit)"
	}
}

/// iOS 15/16 presentation: the Form in its own navigation bar with a Done button,
/// shown as an overlay card while `visible` is true.
struct SettingsView: View {
	@Binding var visible: Bool

	init(visible: Binding<Bool>) {
		_visible = visible
	}

	var body: some View {
		ZStack {
			if visible {
				// Background
				Rectangle()
					.fill(Color.init(red: 0, green: 0, blue: 0, opacity: 0.67))
					.edgesIgnoringSafeArea(.all)
			}
		}

		ZStack {
			if visible {
				NavigationView {
					SettingsForm()
						.navigationBarTitleDisplayMode(.inline)
						.toolbar {
							ToolbarItem(placement: .confirmationAction) {
								Button("Done", action: saveAndExit)
							}
						}
				}
				.navigationViewStyle(.stack)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.padding()
			}
		}
		.preferredColorScheme(appScheme)
		.scaleEffect(visible ? 1 : 0, anchor: .zero)
	}

	func saveAndExit() {
		// settings are already persisted by SettingsStore on every change
		withAnimation(.easeInOut(duration: 0.24)) {
			visible = false
		}
	}
}

/// A menu-style Picker row: title on the left, current choice on the right.
private struct MenuPickerRow<Value: Hashable>: View {
	let title: String
	@Binding var selection: Value
	let options: [Choice<Value>]

	init(_ title: String, selection: Binding<Value>, options: [Choice<Value>]) {
		self.title = title
		_selection = selection
		self.options = options
	}

	var body: some View {
		if #available(iOS 16, *) {
			picker
		} else {
			// iOS 15 menu pickers in a Form don't show their label, so lay it out by hand
			HStack {
				Text(title)
				Spacer()
				picker.labelsHidden()
			}
		}
	}

	private var picker: some View {
		Picker(title, selection: $selection) {
			ForEach(options.indices, id: \.self) { i in
				Text(options[i].label).tag(options[i].value)
			}
		}
		.pickerStyle(.menu)
	}
}

/// A Slider row with its title and the current value shown above the track.
private struct ValueSliderRow: View {
	let title: String
	@Binding var value: Double
	let range: ClosedRange<Double>
	let step: Double

	init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
		self.title = title
		_value = value
		self.range = range
		self.step = step
	}

	private var valueText: String { String(format: "%.1f", value) }

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			if #available(iOS 16, *) {
				LabeledContent(title) {
					Text(valueText).monospacedDigit()
				}
			} else {
				HStack {
					Text(title)
					Spacer()
					Text(valueText)
						.monospacedDigit()
						.foregroundColor(.secondary)
				}
			}
			Slider(value: $value, in: range, step: step) {
				Text(title)
			}
		}
		.padding(.vertical, 2)
	}
}

struct SettingsView_Previews: PreviewProvider {
	@State static var value: Bool = true

	static var previews: some View {
		SettingsView(visible: $value)
	}
}
