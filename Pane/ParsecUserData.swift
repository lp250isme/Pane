struct ParsecUserDataVideo: Codable {
	var encoderFPS: Int = 0
	var resolutionX: Int = 0
	var resolutionY: Int = 0
	var fullFPS: Bool = false
	var hostOS = 0
	var output = "none"
	var encoderMaxBitrate: Int = 50
}

struct ParsecUserDataVideoConfig: Codable {
	var virtualMicrophone: Int = 0
	var virtualTablet: Int = 0
	var video: [ParsecUserDataVideo] = [
		ParsecUserDataVideo(),
		ParsecUserDataVideo(),
		ParsecUserDataVideo()
	]
}

struct ParsecDisplayConfig: Codable, Hashable {
	var name: String = ""
	var adapterName: String = ""
	var id: String = ""
}

enum ParsecUserDataType: UInt32 {
	// plain UTF-8 text both ways, as in the SDK's own client example; the host can turn it off (app_copy_paste)
	case clipboard = 7
	case getVideoConfig = 9
	case getAdapterInfo = 10
	case setVideoConfig = 11
}

// Hosts differ in which keys they send (a Mac host is not a Windows one); a missing key must not
// throw away the whole reply, or the bitrate and display state never reach the menu.
extension ParsecUserDataVideo {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		encoderFPS = try c.decodeIfPresent(Int.self, forKey: .encoderFPS) ?? 0
		resolutionX = try c.decodeIfPresent(Int.self, forKey: .resolutionX) ?? 0
		resolutionY = try c.decodeIfPresent(Int.self, forKey: .resolutionY) ?? 0
		fullFPS = try c.decodeIfPresent(Bool.self, forKey: .fullFPS) ?? false
		hostOS = try c.decodeIfPresent(Int.self, forKey: .hostOS) ?? 0
		output = try c.decodeIfPresent(String.self, forKey: .output) ?? "none"
		encoderMaxBitrate = try c.decodeIfPresent(Int.self, forKey: .encoderMaxBitrate) ?? 0
	}
}

extension ParsecUserDataVideoConfig {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		virtualMicrophone = try c.decodeIfPresent(Int.self, forKey: .virtualMicrophone) ?? 0
		virtualTablet = try c.decodeIfPresent(Int.self, forKey: .virtualTablet) ?? 0
		video = try c.decodeIfPresent([ParsecUserDataVideo].self, forKey: .video) ?? []
	}
}

extension ParsecDisplayConfig {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
		adapterName = try c.decodeIfPresent(String.self, forKey: .adapterName) ?? ""
		id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
	}
}
