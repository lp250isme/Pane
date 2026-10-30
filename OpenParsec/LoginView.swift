import SwiftUI
import os

struct LoginView: View {
	var controller: ContentView?

	@State var inputEmail: String = ""
	@State var inputPassword: String = ""
	@State var inputTFA: String = ""
	@State var isTFAOn: Bool = false
	@State private var presentTFAAlert = false
	@State var isLoading: Bool = false
	@State var showAlert: Bool = false
	@State var alertText: String = ""

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	private enum Field: Hashable {
		case email, password, tfa
	}

	@FocusState private var focus: Field?

	var body: some View {
		ZStack {
			Color(uiColor: .systemGroupedBackground)
				.ignoresSafeArea()

			GeometryReader { geo in
				ScrollView {
					VStack(spacing: 28) {
						header
						credentials
						signInButton
					}
					.padding(.horizontal, 20)
					.padding(.vertical, 32)
					.frame(maxWidth: 420)
					// centred on tall screens, scrolls when the keyboard or landscape leaves no room
					.frame(maxWidth: .infinity, minHeight: geo.size.height)
					.disabled(isLoading) // Disable when loading
				}
				.dismissKeyboardOnScroll()
			}

			// 2FA prompt
			if presentTFAAlert {
				PromptOverlay {
					tfaPrompt
				}
				.disabled(isLoading)
				.onAppear { focus = .tfa }
				.transition(.opacity)
			}
		}
		.animation(.default, value: presentTFAAlert)
		.preferredColorScheme(appScheme)
		.alert(isPresented: $showAlert) {
			Alert(title: Text("Login Failed"), message: Text(alertText))
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in retryRestore() }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retryRestore() }
	}

	private var header: some View {
		VStack(spacing: 12) {
			Image("IconTransparent")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: 88, height: 88)
				.accessibilityHidden(true)
			VStack(spacing: 4) {
				Text("OpenParsec")
					.font(.largeTitle.bold())
				Text("Sign in with your Parsec account")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.multilineTextAlignment(.center)
		}
	}

	private var credentials: some View {
		VStack(spacing: 0) {
			TextField("Email", text: $inputEmail)
				.disableAutocorrection(true)
				.autocapitalization(.none)
				.keyboardType(.emailAddress)
				.textContentType(.emailAddress)
				.submitLabel(.next)
				.focused($focus, equals: .email)
				.onSubmit { focus = .password }
				.padding(.horizontal, 16)
				.frame(minHeight: 50)
			Divider()
				.padding(.leading, 16)
			SecureField("Password", text: $inputPassword)
				.disableAutocorrection(true)
				.autocapitalization(.none)
				.textContentType(.password)
				.submitLabel(.go)
				.focused($focus, equals: .password)
				.onSubmit { authenticate() }
				.padding(.horizontal, 16)
				.frame(minHeight: 50)
		}
		.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
	}

	private var signInButton: some View {
		Button(action: { authenticate() }) {
			ZStack {
				Text("Sign In")
					.fontWeight(.semibold)
					.opacity(isLoading && !presentTFAAlert ? 0 : 1)
				if isLoading && !presentTFAAlert {
					ProgressView()
						.accessibilityLabel("Loading...")
				}
			}
			.frame(maxWidth: .infinity)
		}
		.controlSize(.large)
		.buttonBorderShape(.capsule)
		.prominentActionStyle()
	}

	private var tfaPrompt: some View {
		Group {
			Image(systemName: "lock.shield")
				.font(.largeTitle)
				.foregroundStyle(.tint)
				.accessibilityHidden(true)
			VStack(spacing: 4) {
				Text("Two-Factor Authentication")
					.font(.headline)
				Text("Please enter your 2FA code from your authenticator app")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.multilineTextAlignment(.center)
			TextField("2FA Code", text: $inputTFA)
				.disableAutocorrection(true)
				.autocapitalization(.none)
				.textContentType(.oneTimeCode)
				.font(.title3.monospacedDigit())
				.multilineTextAlignment(.center)
				.submitLabel(.done)
				.focused($focus, equals: .tfa)
				.onSubmit { authenticate(inputTFA) }
				.padding(.horizontal, 12)
				.frame(minHeight: 48)
				.background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			HStack(spacing: 12) {
				Button(role: .cancel, action: { presentTFAAlert = false }) {
					Text("Cancel")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				Button(action: { authenticate(inputTFA) }) {
					ZStack {
						Text("Enter")
							.fontWeight(.semibold)
							.opacity(isLoading ? 0 : 1)
						if isLoading {
							ProgressView()
								.accessibilityLabel("Loading...")
						}
					}
					.frame(maxWidth: .infinity)
				}
				.prominentActionStyle()
			}
			.controlSize(.large)
			.buttonBorderShape(.capsule)
		}
	}

	private var fieldCornerRadius: CGFloat {
		if #available(iOS 26, *) { return 26 }
		return 12
	}

	func retryRestore() {
		if !isLoading && !presentTFAAlert, let c = controller {
			c.retryRestore()
		}
	}

	func saveToKeychain(data: Data, key: String) {
		SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess else {
			print("Error saving to Keychain: \(status)")
			return
		}
		print("Data saved to Keychain.")
	}

	func authenticate(_ tfa: String? = "") {
		#if DEBUG
		if inputEmail == "test@example.com" { // skip authentication (DEBUG ONLY)
			if let c = controller {
				c.setView(.main)
			}
			return
		}
		#endif

		withAnimation { isLoading = true }

		let apiURL = URL(string: "https://kessel-api.parsec.app/v1/auth")!

		var request = URLRequest(url: apiURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")
		request.httpBody = try? JSONSerialization.data(withJSONObject:
		[
			"email": inputEmail,
			"password": inputPassword,
			"tfa": tfa
		], options: [])

		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			DispatchQueue.main.async {
				isLoading = false
				if let data = data {
					guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
						alertText = "Bad response from the server"
						showAlert = true
						return
					}
					let decoder = JSONDecoder()

					if statusCode == 201 { // 201 Created
						// store it and recover it from the next app opening, so people won't swear
						guard let info: ClientInfo = try? decoder.decode(ClientInfo.self, from: data) else {
							alertText = "Bad response from the server"
							showAlert = true
							return
						}
						NetworkHandler.clinfo = info

						saveToKeychain(data: data, key: GLBDataModel.shared.SessionKeyChainKey)

						if let c = controller {
							print("*** Login succeeded! ***")
							c.setView(.main)
						}
					} else if statusCode >= 400 { // 4XX client errors
						guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else {
							alertText = "Login failed (HTTP \(statusCode))"
							showAlert = true
							return
						}

						let json = try? JSONSerialization.jsonObject(with: data, options: [])
						if let dict = json as? [String: Any], let isTFARequired = dict["tfa_required"] as? Bool {
							print("Code output:")
							print(dict)
							if isTFARequired {
								presentTFAAlert = true
							} else {
								alertText = "Error: \(info)"
								showAlert = true
							}
						} else {
							alertText = info.error
							showAlert = true
						}
					} else {
						alertText = "Login failed (HTTP \(statusCode))"
						showAlert = true
					}
				} else {
					alertText = error?.localizedDescription ?? "Could not reach the server"
					showAlert = true
				}
			}
		}
		task.resume()
	}
}

private extension View {
	@ViewBuilder
	func dismissKeyboardOnScroll() -> some View {
		if #available(iOS 16, *) {
			self.scrollDismissesKeyboard(.interactively)
		} else {
			self
		}
	}
}

struct LoginView_Previews: PreviewProvider {
	static var previews: some View {
		LoginView(nil)
	}
}
