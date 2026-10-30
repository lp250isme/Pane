import SwiftUI
import ParsecSDK

struct MainView: View {
	var controller: ContentView?

	@State private var page: Page = .hosts
	@State private var sidebarSelection: Page? = .hosts

	// Host page vars
	@State var hostCountStr: String = String(localized: "\(0) hosts")
	@State var refreshTime: String = ""

	@State var hosts: [IdentifiableHostInfo] = []

	// Friend page vars
	@State var friendCountStr: String = String(localized: "\(0) friends")

	@State var userInfo: IdentifiableUserInfo?
	@State var friends: [IdentifiableUserInfo] = []

	// Global vars
	@State var showBaseAlert: Bool = false
	@State var baseAlertText: String = ""

	@State var showLogoutAlert: Bool = false

	@State var isConnecting: Bool = false
	@State var waitingForApproval: Bool = false
	@State var retryingConnect: Bool = false
	@State var connectPolls = 0
	@State var connectingToName: String = ""
	@State var pollTimer: Timer?
	@State var approvalStartedAt: Date?
	@State var connectStartedAt = Date()

	@State var isRefreshing: Bool = false
	@State var refreshError: String?

	@State var inSettings: Bool = false
	@State var sessionExpired: Bool = false

	@State private var lastHostShown: String?

	var busy: Bool {
		isConnecting || inSettings
	}

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var body: some View {
		ZStack {
			main
				.onAppear(perform: initView)
				.onDisappear {
					if ParsecBackgroundManager.shared.ownsStream(ParsecBackgroundManager.shared.keyWindowScene) {
						ParsecBackgroundManager.shared.onShortcutReconnect = nil
					}
				}
				.disabled(busy) // disable view if busy
				// on the root, the iOS 17 detail is off screen while the sidebar shows on iPhone
				.alert(isPresented: $showBaseAlert) {
					Alert(title: Text(baseAlertText))
				}

			// Settings overlay, iOS 16 and earlier; iOS 17 shows settings in the sidebar
			if #available(iOS 17.0, *) {
			} else {
				SettingsView(visible: $inSettings)
					.foregroundColor(Color("Foreground"))
			}

			// Loading elements
			if isConnecting {
				PromptOverlay {
					ProgressView()
						.controlSize(.large)
					VStack(spacing: 4) {
						Text(connectingToName)
							.font(.headline)
							.lineLimit(2)
						Text(waitingForApproval ? "Waiting for the host to approve you..." : retryingConnect ? "No answer, trying again..." : "Requesting connection...")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
					Button(role: .cancel, action: cancelConnection) {
						Text("Cancel")
							.frame(minWidth: 120)
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
				}
				.transition(.opacity)
				.zIndex(1)
			}
		}
		// the overlay above used to carry this; on iOS 17 it is gone
		.preferredColorScheme(appScheme)
	}

	@ViewBuilder
	private var main: some View {
		if #available(iOS 17.0, *) {
			sidebarLayout
		} else {
			legacyLayout
		}
	}

	@available(iOS 17.0, *)
	private var sidebarLayout: some View {
		CompactDetailSplit {
			// lets nil through: a compact pop clears it, so tapping the same row pushes again
			List(selection: Binding<Page?>(get: { sidebarSelection }, set: { sidebarSelection = $0; if let p = $0 { page = p } })) {
				Label("Hosts", systemImage: "desktopcomputer").tag(Page.hosts)
				Label("Friends", systemImage: "person.2.fill").tag(Page.friends)
				Section {
					Label("Settings", systemImage: "gear").tag(Page.settings)
					Button(role: .destructive, action: { showLogoutAlert = true }) {
						Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
					}
				}
			}
			.navigationTitle("Pane")
			.alert(isPresented: $showLogoutAlert) {
				Alert(title: Text("Are you sure you want to logout?"), primaryButton: .destructive(Text("Logout"), action: logout), secondaryButton: .cancel(Text("Cancel")))
			}
		} detail: {
			nativePages
				.navigationTitle(page == .hosts ? "Hosts" : page == .friends ? "Friends" : "Settings")
				.countSubtitle(pageCountStr)
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					if page == .hosts {
						ToolbarItem(placement: .primaryAction) {
							Button(action: refreshHosts) {
								Label("Refresh", systemImage: "arrow.clockwise")
							}
							.disabled(isRefreshing)
						}
					}
				}
		}
	}

	// iOS 16 and earlier
	private var legacyLayout: some View {
		ZStack {
			Rectangle()
				.fill(Color("BackgroundTab"))
				.edgesIgnoringSafeArea(.all)
			Rectangle()
				.fill(Color("BackgroundGray"))
				.padding(.vertical, 52)
				// iPhone Duo landscape puts the status bar in a trailing column; fill under it
				.edgesIgnoringSafeArea(.horizontal)

			VStack {
				// Navigation controls
				HStack {
					Button(action: { showLogoutAlert = true }, label: { Image("SymbolExit").scaleEffect(x: -1) })
						.padding()
						.alert(isPresented: $showLogoutAlert) {
							Alert(title: Text("Are you sure you want to logout?"), primaryButton: .destructive(Text("Logout"), action: logout), secondaryButton: .cancel(Text("Cancel")))
						}
//					Button(action: {
//						if let c = controller
//						{
//							c.setView(.test)
//
//						}
//						
//					}, label: {
//						Text("Show TestView")
//					})

					Spacer()
					HStack {
						if page == .hosts {
							// Probably not the best solution for equal spacing, but I don't know how to do math properly in SwiftUI. Please send me an issue if you have a better solution.
							Image(systemName: "arrow.clockwise")
								.padding(4)
								.opacity(0)

							Text(hostCountStr)
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
							Button(action: refreshHosts, label: { Image(systemName: "arrow.clockwise") })
								.padding(4)
								.disabled(isRefreshing)
								.opacity(isRefreshing ? 0.4 : 1)
						} else if page == .friends {
							Text(friendCountStr)
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
						}
					}
					Spacer()
					Button(action: { withAnimation(.easeInOut(duration: 0.24)) { inSettings = true } }, label: { Image(systemName: "gear") })
						.padding()
				}
				.foregroundColor(Color("AccentColor"))
				.background(Color("BackgroundTab")
					.frame(height: 52)
					.shadow(color: Color("Shading"), radius: 4, y: 6)
					.mask(Rectangle().frame(height: 80).offset(y: 50))
					.edgesIgnoringSafeArea(.horizontal)
				)
				.zIndex(1)

				pages
					.padding(.top, -8)

				// Page controls
				HStack {
					Spacer()
					Button(action: { page = .hosts }, label:
					{
						VStack {
							Image(systemName: "desktopcomputer")
							Text("Hosts")
						}
					})
					.foregroundColor(Color(page == .hosts ? "AccentColor" : "ForegroundInactive"))
					.disabled(page == .hosts)
					Spacer()
					Button(action: { page = .friends }, label:
					{
						VStack {
							Image(systemName: "person.2.fill")
							Text("Friends")
						}
					})
					.foregroundColor(Color(page == .friends ? "AccentColor" : "ForegroundInactive"))
					.disabled(page == .friends)
					Spacer()
				}
				.padding([.leading, .bottom, .trailing], 4)
				.background(Color("BackgroundTab")
					.padding(.top, -8)
					.shadow(color: Color("Shading"), radius: 4, y: -2)
					.mask(Rectangle().frame(height: 80).offset(y: -50))
					.edgesIgnoringSafeArea(.horizontal)
				)
				.zIndex(1)
			}
		}
		.foregroundColor(Color("Foreground"))
	}

	private var pages: some View {
		ZStack {
			// Hosts page
			ScrollView(.vertical) {
				VStack {
					if sessionExpired {
						HStack {
							Text("Your Parsec session expired")
								.foregroundColor(Color("Foreground"))
							Spacer()
							Button(action: logout) {
								Text("Sign In")
									.fontWeight(.semibold)
									.foregroundColor(Color("AccentColor"))
									.frame(minWidth: 44, minHeight: 44)
									.contentShape(Rectangle())
							}
						}
						.padding(.horizontal, 12)
						.padding(.vertical, 2)
						.background(Rectangle().fill(Color("BackgroundPrompt")))
						.cornerRadius(8)
						.frame(maxWidth: 400)
						.padding(.horizontal)
					}
					if let refreshError = refreshError {
						HStack {
							Text(refreshError)
								.foregroundColor(Color("Foreground"))
							Spacer()
							Button(action: refreshHosts) {
								Text("Retry")
									.fontWeight(.semibold)
									.foregroundColor(Color("AccentColor"))
									.frame(minWidth: 44, minHeight: 44)
									.contentShape(Rectangle())
							}
						}
						.padding(.horizontal, 12)
						.padding(.vertical, 2)
						.background(Rectangle().fill(Color("BackgroundPrompt")))
						.cornerRadius(8)
						.frame(maxWidth: 400)
						.padding(.horizontal)
					}
					if isRefreshing {
						HStack(spacing: 8) {
							ActivityIndicator(isAnimating: $isRefreshing, style: .medium, tint: UIColor(named: "Foreground") ?? .white)
								.frame(width: 20, height: 20)
							Text("Refreshing hosts...")
								.foregroundColor(Color("Foreground"))
						}
					} else if !refreshTime.isEmpty {
						Text(refreshTime)
							.multilineTextAlignment(.center)
							.opacity(0.5)
					}
					if let lastHost = lastHostShown, !isConnecting {
						VStack(spacing: 0) {
							HStack {
								VStack(alignment: .leading, spacing: 4) {
									Text("Last connected")
										.font(.system(size: 12))
										.opacity(0.5)
									Text(lastHost)
										.font(.system(size: 16, weight: .medium))
								}
								Spacer()
								Button(action: reconnectLastHost) {
									Text("Reconnect")
										.foregroundColor(Color(.systemBackground))
										.padding(.horizontal, 12)
										.padding(.vertical, 6)
										.background(Color("AccentColor"))
										.cornerRadius(8)
								}
								Button(action: clearLastHost) {
									Image(systemName: "xmark")
										.foregroundColor(Color("Foreground"))
										.opacity(0.5)
										.padding(8)
								}
							}
							.padding()
							HStack {
								Toggle("Reconnect on app launch", isOn: Binding(
									get: { SettingsHandler.autoConnectOnLaunch },
									set: { SettingsHandler.autoConnectOnLaunch = $0 }
								))
								.font(.system(size: 13))
								.opacity(0.7)
							}
							.padding(.horizontal)
							.padding(.bottom, 10)
						}
						.frame(maxWidth: 400)
						.background(Rectangle().fill(Color("BackgroundCard")))
						.cornerRadius(8)
					}
					ForEach(hosts) { i in
						ZStack {
							VStack {
								URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=64,h=64,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(i.user.id))/avatar"),
										output:
										{
											$0
												.resizable()
												.aspectRatio(contentMode: .fit)
												.frame(width: 64, height: 64)
												.cornerRadius(8)
										},
										placeholder:
										{
											Image("IconTransparent")
												.resizable()
												.aspectRatio(contentMode: .fit)
												.frame(width: 64, height: 64)
												.background(Rectangle().fill(Color("BackgroundPrompt")))
												.cornerRadius(8)
										})
								Text(i.hostname)
									.font(.system(size: 20, weight: .medium))
									.multilineTextAlignment(.center)
								Text("\(i.user.name)#\(String(i.user.id))")
									.font(.system(size: 16, weight: .medium))
									.multilineTextAlignment(.center)
									.opacity(0.5)
								Button(action: { connectTo(i) }) {
									ZStack {
										Rectangle()
											.fill(Color("AccentColor"))
											.cornerRadius(8)
										Text("Connect")
											.foregroundColor(Color(.systemBackground))
											.padding(8)
									}
									.frame(maxWidth: 100)
								}
							}

							if i.connections > 0 {
								VStack {
									HStack {
										Image(systemName: "person.fill")
										Text(String(i.connections))
											.font(.system(size: 16, weight: .medium))
										Spacer()
									}
									Spacer()
								}
							}
						}
						.padding()
						.frame(maxWidth: 400)
						.background(Rectangle().fill(Color("BackgroundCard")))
						.cornerRadius(8)
						.contextMenu {
							Button(action: { UIPasteboard.general.string = i.hostname }) {
								Label("Copy Name", systemImage: "doc.on.doc")
							}
						}
					}
				}
				.padding()
			}
			.zIndex(page == .hosts ? 0 : -1)
			.disabled(page != .hosts)
			.opacity(page == .hosts ? 1 : 0)

			// Friends page
			ScrollView(.vertical) {
				VStack {
					if let user = userInfo {
						Text("You")
							.multilineTextAlignment(.center)
							.opacity(0.5)
						HStack {
							URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=48,h=48,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(user.id))/avatar"),
								output:
								{
									$0
										.resizable()
										.aspectRatio(contentMode: .fit)
										.frame(width: 48, height: 48)
										.cornerRadius(6)
								},
								placeholder:
								{
									Image("IconTransparent")
										.resizable()
										.aspectRatio(contentMode: .fit)
										.frame(width: 48, height: 48)
										.background(Rectangle().fill(Color("BackgroundPrompt")))
										.cornerRadius(6)
								})
							Text("\(user.username)#\(String(user.id))")
								.font(.system(size: 16, weight: .medium))
								.multilineTextAlignment(.center)
							Spacer()
						}
						.padding(8)
						.background(Color("BackgroundCard"))
						.cornerRadius(12)
					}
					if friends.count > 0 {
						Text("Friends")
							.multilineTextAlignment(.center)
							.opacity(0.5)
						ForEach(friends) { i in
							HStack {
								URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=48,h=48,fit=crop,background=white,q=90,f=jpeg/avatars/\(String(i.id))/avatar"),
									output:
									{
										$0
											.resizable()
											.aspectRatio(contentMode: .fit)
											.frame(width: 48, height: 48)
											.cornerRadius(6)
									},
									placeholder:
									{
										Image("IconTransparent")
											.resizable()
											.aspectRatio(contentMode: .fit)
											.frame(width: 48, height: 48)
											.background(Rectangle().fill(Color("BackgroundPrompt")))
											.cornerRadius(6)
									})
								Text("\(i.username)#\(String(i.id))")
									.font(.system(size: 16, weight: .medium))
									.multilineTextAlignment(.center)
								Spacer()
//										Button(action:{ }, label:{ Image(systemName:"ellipsis.circle.fill") })
//											.font(.system(size:20))
//											.foregroundColor(Color("AccentColor"))
//											.padding(8)
							}
							.padding(8)
							.background(Color("BackgroundCard"))
							.cornerRadius(12)
						}
					}
				}
				.padding()
			}
			.zIndex(page == .friends ? 0 : -1)
			.disabled(page != .friends)
			.opacity(page == .friends ? 1 : 0)
		}
		.frame(maxWidth: .infinity)
			.foregroundColor(Color("Foreground"))
	}

	// host or friend count once loaded; nav subtitle on iOS 26, section header before
	private var pageCountStr: String? {
		switch page {
		case .hosts: return refreshTime.isEmpty ? nil : hostCountStr
		case .friends: return friendCountStr
		case .settings: return nil
		}
	}

	// iOS 17+ page content: system lists, the grouped background comes from the list
	@available(iOS 17.0, *)
	@ViewBuilder
	private var nativePages: some View {
		switch page {
		case .hosts: nativeHostsList
		case .friends: nativeFriendsList
		case .settings: SettingsForm()
		}
	}

	@available(iOS 17.0, *)
	private var nativeHostsList: some View {
		List {
			if sessionExpired || refreshError != nil {
				Section {
					if sessionExpired {
						HStack {
							Label {
								Text("Your Parsec session expired")
							} icon: {
								Image(systemName: "person.crop.circle.badge.exclamationmark")
									.foregroundStyle(.orange)
							}
							Spacer()
							Button("Sign In", action: logout)
								.fontWeight(.semibold)
								.buttonStyle(.borderless)
						}
					}
					if let refreshError = refreshError {
						HStack {
							Label {
								Text(refreshError)
							} icon: {
								Image(systemName: "exclamationmark.triangle.fill")
									.foregroundStyle(.orange)
							}
							Spacer()
							Button("Retry", action: refreshHosts)
								.fontWeight(.semibold)
								.buttonStyle(.borderless)
						}
					}
				}
			}

			if let lastHost = lastHostShown, !isConnecting {
				Section("Last connected") {
					HStack(spacing: 12) {
						Label(lastHost, systemImage: "clock.arrow.circlepath")
							.font(.headline)
							.lineLimit(1)
						Spacer()
						Button("Reconnect", action: reconnectLastHost)
							.buttonStyle(.borderedProminent)
							.onAccentLabel()
							.buttonBorderShape(.capsule)
							.controlSize(.small)
						Button(action: clearLastHost) {
							Image(systemName: "xmark.circle.fill")
								.font(.title3)
								.foregroundStyle(.secondary)
						}
						.buttonStyle(.borderless)
						.accessibilityLabel("Forget last host")
					}
					Toggle("Reconnect on app launch", isOn: Binding(
						get: { SettingsHandler.autoConnectOnLaunch },
						set: { SettingsHandler.autoConnectOnLaunch = $0 }
					))
				}
			}

			Section {
				ForEach(hosts) { i in
					HStack(spacing: 12) {
						avatar(userId: i.user.id, size: 44)
						VStack(alignment: .leading, spacing: 2) {
							Text(i.hostname)
								.font(.headline)
							Text("\(i.user.name)#\(String(i.user.id))")
								.font(.subheadline)
								.foregroundStyle(.secondary)
							if i.connections > 0 {
								Label(String(i.connections), systemImage: "person.fill")
									.font(.caption)
									.foregroundStyle(.secondary)
									.accessibilityLabel("\(i.connections) connected")
							}
						}
						Spacer()
						Button("Connect") { connectTo(i) }
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.small)
							.accessibilityLabel("Connect to \(i.hostname)")
					}
					.padding(.vertical, 2)
					.contextMenu {
						Button(action: { connectTo(i) }) {
							Label("Connect", systemImage: "play.display")
						}
						Button(action: { UIPasteboard.general.string = i.hostname }) {
							Label("Copy Name", systemImage: "doc.on.doc")
						}
					}
				}
				if hosts.isEmpty, !isRefreshing, !sessionExpired, refreshError == nil, !refreshTime.isEmpty {
					ContentUnavailableView("No Hosts", systemImage: "desktopcomputer", description: Text("Computers running Parsec on your account show up here."))
						.listRowBackground(Color.clear)
				}
			} header: {
				if #available(iOS 26, *) {
					Text("Hosts")
				} else {
					Text(refreshTime.isEmpty ? String(localized: "Hosts") : hostCountStr)
				}
			} footer: {
				if isRefreshing {
					HStack(spacing: 8) {
						ProgressView()
							.controlSize(.small)
						Text("Refreshing hosts...")
					}
				} else if !refreshTime.isEmpty {
					Text(refreshTime)
				}
			}
		}
		.listStyle(.insetGrouped)
		.refreshable {
			refreshHosts()
			// refreshHosts returns at once; hold the spinner until the request lands
			while isRefreshing {
				try? await Task.sleep(for: .milliseconds(100))
			}
		}
	}

	@available(iOS 17.0, *)
	private var nativeFriendsList: some View {
		List {
			if let user = userInfo {
				Section("You") {
					HStack(spacing: 12) {
						avatar(userId: user.id, size: 40)
						Text("\(user.username)#\(String(user.id))")
							.font(.body.weight(.medium))
					}
				}
			}
			if friends.count > 0 {
				Section {
					ForEach(friends) { i in
						HStack(spacing: 12) {
							avatar(userId: i.id, size: 40)
							Text("\(i.username)#\(String(i.id))")
						}
					}
				} header: {
					if #available(iOS 26, *) {
						Text("Friends")
					} else {
						Text(friendCountStr)
					}
				}
			}
		}
		.listStyle(.insetGrouped)
		.refreshable {
			refreshSelf()
			refreshFriends()
		}
	}

	private func avatar(userId: Int, size: Int) -> some View {
		URLImage(url: URL(string: "https://parsecusercontent.com/cors-resize-image/w=\(size * 2),h=\(size * 2),fit=crop,background=white,q=90,f=jpeg/avatars/\(String(userId))/avatar"),
			output: {
				$0
					.resizable()
					.aspectRatio(contentMode: .fill)
			},
			placeholder: {
				Image(systemName: "person.fill")
					.font(.system(size: CGFloat(size) * 0.45))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color(uiColor: .tertiarySystemFill))
			})
			.frame(width: CGFloat(size), height: CGFloat(size))
			.clipShape(Circle())
			.accessibilityHidden(true)
	}

	func initView() {
		lastHostShown = ParsecBackgroundManager.shared.lastPeerId != nil ? ParsecBackgroundManager.shared.lastHostname : nil
		refreshHosts()
		refreshSelf()
		refreshFriends()

		// the reconnect hooks are app wide; a second window must not take them from the streaming one
		// ponytail: assumes the appearing window is key, true for a newly opened window
		guard ParsecBackgroundManager.shared.ownsStream(ParsecBackgroundManager.shared.keyWindowScene) else { return }

		registerReconnectHooks()

		NetworkWatcher.shared.onReturn = {
			guard NetworkHandler.clinfo != nil, !ParsecBackgroundManager.shared.hasActiveConnection else { return }
			refreshHosts()
			refreshFriends()
		}
		NetworkWatcher.shared.start()

		let pending = ParsecBackgroundManager.shared.reconnectPending
		ParsecBackgroundManager.shared.reconnectPending = false

		NetworkWatcher.shared.whenKnown {
			if (SettingsHandler.autoConnectOnLaunch && ParsecBackgroundManager.shared.resumeOnLaunch || pending) && !isConnecting && !ParsecBackgroundManager.shared.hasActiveConnection, ParsecBackgroundManager.shared.lastPeerId != nil {
				reconnectLastHost()
			}
		}
	}

	// connectTo calls this too, so the hooks follow whichever window is streaming
	func registerReconnectHooks() {
		ParsecBackgroundManager.shared.onShouldReconnect = { peerId in
			if let host = hosts.first(where: { $0.id == peerId }) {
				connectTo(host)
			} else {
				refreshHosts()
			}
		}
		ParsecBackgroundManager.shared.onShortcutReconnect = {
			if !isConnecting { reconnectLastHost() }
		}
	}

	func reconnectLastHost() {
		guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
		let hostname = ParsecBackgroundManager.shared.lastHostname ?? peerId
		let user = UserInfo(id: 0, name: "", warp: false, team_id: "")
		let stub = IdentifiableHostInfo(id: peerId, hostname: hostname, user: user, connections: 0)
		appNote("[connect] last host from the saved id, host list \(hosts.isEmpty ? "not loaded yet" : "loaded")")
		connectTo(stub)
	}

	func clearLastHost() {
		ParsecBackgroundManager.shared.disableAutoReconnect()
		lastHostShown = nil
	}

	func refreshHosts() {
		guard !isRefreshing else { return }
		withAnimation {
			isRefreshing = true

			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				isRefreshing = false
				sessionExpired = true
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/v2/hosts?mode=desktop&public=false")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					defer { isRefreshing = false }

					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							refreshError = nil
							expireSession()
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							sessionExpired = false
							guard let info: HostInfoList = try? decoder.decode(HostInfoList.self, from: data) else {
								refreshError = String(localized: "Couldn't refresh hosts: bad response")
								return
							}
							refreshError = nil
							hosts.removeAll()
							if let datas = info.data {
								datas.forEach { h in
									hosts.append(IdentifiableHostInfo(id: h.peer_id, hostname: h.name, user: h.user, connections: h.players))
								}
							}
							if let lastId = ParsecBackgroundManager.shared.lastPeerId, let current = hosts.first(where: { $0.id == lastId }), current.hostname != ParsecBackgroundManager.shared.lastHostname {
								ParsecBackgroundManager.shared.lastHostname = current.hostname
								if lastHostShown != nil { lastHostShown = current.hostname }
							}

							hostCountStr = hosts.count == 1 ? String(localized: "\(hosts.count) host") : String(localized: "\(hosts.count) hosts")

							let formatter = DateFormatter()
							formatter.dateStyle = .short
							formatter.timeStyle = .short
							refreshTime = String(localized: "Last refreshed at \(formatter.string(from: Date()))")
						} else if statusCode == 403, let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) { // 403 Forbidden
							refreshError = String(localized: "Couldn't refresh hosts: \(info.error)")
						} else {
							refreshError = String(localized: "Couldn't refresh hosts (HTTP \(statusCode))")
						}
					} else {
						refreshError = String(localized: "Can't reach Parsec")
					}
				}
			}
			task.resume()
		}
	}

	func refreshSelf() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/me")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							expireSession()
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let selfInfo = try? decoder.decode(SelfInfo.self, from: data) else { return }
							userInfo = IdentifiableUserInfo(id: selfInfo.data.id, username: selfInfo.data.name)
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = String(localized: "Error gathering user info: \(info.error)")
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func refreshFriends() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/friendships")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							expireSession()
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let info: FriendInfoList = try? decoder.decode(FriendInfoList.self, from: data) else { return }
							friends.removeAll()
							if let datas = info.data {
								datas.forEach { f in
									friends.append(IdentifiableUserInfo(id: f.user_id, username: f.user_name))
								}
							}

							friendCountStr = friends.count == 1 ? String(localized: "\(friends.count) friend") : String(localized: "\(friends.count) friends")
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = String(localized: "Error gathering friends: \(info.error)")
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func connectTo(_ who: IdentifiableHostInfo, retried: Bool = false) {
		if NetworkWatcher.shared.noNetwork {
			appNote("[connect] no network, not trying")
			withAnimation {
				isConnecting = false
				waitingForApproval = false
				retryingConnect = false
			}
			baseAlertText = String(localized: "No network connection")
			showBaseAlert = true
			return
		}

		let keyWindow = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
		// the SDK holds one connection; a second window must not take it over
		if ParsecBackgroundManager.shared.hasActiveConnection, let owner = ParsecBackgroundManager.shared.streamScene, owner !== keyWindow?.windowScene {
			withAnimation {
				isConnecting = false
				waitingForApproval = false
				retryingConnect = false
			}
			baseAlertText = String(localized: "Already streaming in another window")
			showBaseAlert = true
			return
		}
		ParsecBackgroundManager.shared.streamScene = keyWindow?.windowScene
		registerReconnectHooks()

		if let window = keyWindow {
			let scale = window.screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(window.bounds.width * scale), height: Int(window.bounds.height * scale))
		}

		pollTimer?.invalidate()
		pollTimer = nil
		CParsec.initialize()
		DataManager.model.reset()
		ParsecBackgroundManager.shared.reconnectAttempts = 0
		connectingToName = who.hostname
		retryingConnect = retried
		withAnimation { isConnecting = true }

		connectStartedAt = Date()
		let status = CParsec.connect(who.id)
		appNote("[connect] started, status \(status.rawValue)")
		connectPolls = 0
		approvalStartedAt = nil

		// Polling status
		pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
			MainActor.assumeIsolated {
				pollConnect(who)
			}
		}
	}

	func pollConnect(_ who: IdentifiableHostInfo) {
		let status = CParsec.getStatus()
		connectPolls += 1

		if let err = CParsec.setupError, err.at > connectStartedAt, status == PARSEC_CONNECTING || status == CONNECT_WRN_APPROVAL {
			CParsec.setupError = nil
			appNote("[connect] sdk setup failed after \(connectPolls) polls, retried \(retryingConnect): \(err.line)")
			retryOrGiveUp(who)
			return
		}

		if status == PARSEC_CONNECTING {
			// a connection that never gets anywhere (network gone mid-handshake) would spin forever
			if connectPolls >= 45 {
				appNote("[connect] still connecting after \(connectPolls) polls, retried \(retryingConnect)")
				retryOrGiveUp(who)
			}
			return
		}

		if status == CONNECT_WRN_APPROVAL {
			if approvalStartedAt == nil {
				appNote("[connect] status \(status.rawValue) after \(connectPolls) polls, retried \(retryingConnect)")
				if connectPolls >= 20 {
					retryOrGiveUp(who)
					return
				}
			}
			let started = approvalStartedAt ?? Date()
			approvalStartedAt = started
			if !waitingForApproval { withAnimation { waitingForApproval = true } }
			if Date().timeIntervalSince(started) < 60 { return }
		}

		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}
		appNote("[connect] result \(status.rawValue)")

		if status == PARSEC_OK {
			ParsecBackgroundManager.shared.connectionDidGoLive(peerId: who.id, hostname: hosts.first(where: { $0.id == who.id })?.hostname ?? who.hostname)
			if let c = controller {
				c.setView(.parsec)
			}
		} else {
			CParsec.disconnect()
			baseAlertText = status.readable(connecting: true)
			showBaseAlert = true
		}

		pollTimer?.invalidate()
	}

	func retryOrGiveUp(_ who: IdentifiableHostInfo) {
		pollTimer?.invalidate()
		CParsec.disconnect()
		if !retryingConnect {
			connectTo(who, retried: true)
			return
		}
		withAnimation {
			isConnecting = false
			retryingConnect = false
		}
		baseAlertText = String(localized: "\(who.hostname) didn't answer the connection request")
		showBaseAlert = true
	}

	func cancelConnection() {
		appNote("[connect] cancelled")
		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}

		CParsec.disconnect()

		pollTimer?.invalidate()
	}

	// a dead session: the stored one would come back on every launch, and the old host list still offers Connect
	func expireSession() {
		removeFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey)
		NetworkHandler.clinfo = nil
		hosts = []
		lastHostShown = nil
		ParsecBackgroundManager.shared.disableAutoReconnect()
		sessionExpired = true
	}

	func logout() {
		removeFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey)
		NetworkHandler.clinfo = nil
		ParsecBackgroundManager.shared.disableAutoReconnect()
		if let c = controller {
			c.setView(.login)
		}
	}

	func removeFromKeychain(key: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
		let status = SecItemDelete(query as CFDictionary)
		if status == errSecSuccess {
			print("Successfully removed data from keychain.")
		}
	}
}

struct MainView_Previews: PreviewProvider {
	static var previews: some View {
		MainView(nil)
	}
}

struct IdentifiableHostInfo: Identifiable {
	var id: String // Peer ID
	var hostname: String // Computer's Display Name
	var user: UserInfo // User Data
	var connections: Int // User's Connected To This Host
}

struct IdentifiableUserInfo: Identifiable {
	var id: Int // User ID
	var username: String // User Display Name
}

private extension View {
	@ViewBuilder
	func countSubtitle(_ text: String?) -> some View {
		if #available(iOS 26, *), let text = text {
			self.navigationSubtitle(text)
		} else {
			self
		}
	}
}

// a narrow window opens on the page, the sidebar is one back tap away
@available(iOS 17.0, *)
private struct CompactDetailSplit<Sidebar: View, Detail: View>: View {
	@State private var column = NavigationSplitViewColumn.detail
	@ViewBuilder var sidebar: Sidebar
	@ViewBuilder var detail: Detail

	var body: some View {
		NavigationSplitView(preferredCompactColumn: $column) { sidebar } detail: { detail }
	}
}

private enum Page {
	case hosts
	case friends
	case settings // iOS 17 sidebar only; older versions open the SettingsView overlay
}
