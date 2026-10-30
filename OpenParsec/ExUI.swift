import SwiftUI

/**
 * Choice
 *
 * Used to depict a single choice with a given label and value.
 */
struct Choice<T: Hashable> {
	var label: LocalizedStringKey
	var value: T

	init(_ label: LocalizedStringKey, _ value: T) {
		self.label = label
		self.value = value
	}
}

/**
 * Prompt Overlay
 *
 * Dims the screen and shows a centred card for a blocking prompt.
 * Liquid Glass on iOS 26, a material card before.
 */
struct PromptOverlay<Content: View>: View {
	var content: () -> Content

	init(@ViewBuilder content: @escaping () -> Content) {
		self.content = content
	}

	var body: some View {
		ZStack {
			Color.black.opacity(0.4)
				.ignoresSafeArea()
			VStack(spacing: 16, content: content)
				.padding(24)
				.frame(maxWidth: 360)
				.promptCardBackground()
				.padding(24)
				.accessibilityElement(children: .contain)
				.accessibilityAddTraits(.isModal)
		}
	}
}

extension View {
	/// Card surface for prompts: glass on iOS 26, regular material before.
	@ViewBuilder
	func promptCardBackground() -> some View {
		if #available(iOS 26, *) {
			self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
		} else {
			self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
		}
	}

	/// Primary action button: glass prominent on iOS 26, bordered prominent before.
	@ViewBuilder
	func prominentActionStyle() -> some View {
		if #available(iOS 26, *) {
			self.buttonStyle(.glassProminent)
		} else {
			self.buttonStyle(.borderedProminent)
		}
	}
}
