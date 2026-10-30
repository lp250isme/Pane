import Foundation
import SwiftUI
import ParsecSDK
import os

// nil follows the system light / dark setting
var appScheme: ColorScheme? = nil

struct GLBData {
	let SessionKeyChainKey = "OPStoredAuthData"
}

class GLBDataModel {
	static let shared = GLBData()
}

extension String {
	static func fromBuffer(_ ptr: UnsafeMutablePointer<CChar>, length len: Int) -> String {
		// convert C char bytes using the UTF8 encoding
		let nsstr = NSString(bytes: ptr, length: len, encoding: NSUTF8StringEncoding)
		return nsstr! as String
	}
}

class CursorPositionHelper {
	static func toHost(_ xp: Int, _ yp: Int) -> (Int, Int) {
		let xh = CParsec.hostWidth
		let yh = CParsec.hostHeight
		let xc = CParsec.clientWidth
		let yc = CParsec.clientHeight

		let tc = yc / xc
		let th = yh / xh

		var xa: Float
		var ya: Float
		if th < tc {
			xa = Float(xp) * xh / xc
			ya = (Float(yp) - 0.5 * (yc - xc*th)) * xh / xc
		} else {
			ya = Float(yp) * yh / yc
			xa = (Float(xp) - 0.5 * (xc - yc/th)) * yh / yc
		}

		return (Int(ParsecSDKBridge.clamp(xa, minValue: 0, maxValue: CParsec.hostWidth)), Int(ParsecSDKBridge.clamp(ya, minValue: 0, maxValue: CParsec.hostHeight)))
	}

	static func toClient(_ xa: Int, _ ya: Int) -> (Int, Int) {
		let xh = CParsec.hostWidth
		let yh = CParsec.hostHeight
		let xc = CParsec.clientWidth
		let yc = CParsec.clientHeight

		let tc = yc / xc
		let th = yh / xh

		var xp: Float
		var yp: Float
		if th < tc {
			xp = Float(xa) * xc / xh
			yp = Float(ya) * xc / xh + 0.5 * (yc - xc*th)
		} else {
			yp = Float(ya) * yc / yh
			xp = Float(xa) * yc / yh + 0.5 * (xc - yc/th)
		}

		return (Int(ParsecSDKBridge.clamp(xp, minValue: 0, maxValue: CParsec.clientWidth)), Int(ParsecSDKBridge.clamp(yp, minValue: 0, maxValue: CParsec.clientHeight)))
	}
}

class SharedModel: ObservableObject {
	@Published var resolutionX = 0
	@Published var resolutionY = 0
	@Published var bitrate = 0
	@Published var hostDefaultBitrate = 0
	@Published var constantFps = false
	@Published var output = "none"
	@Published var displayConfigs: [ParsecDisplayConfig] = []
	@Published var isBlocked = false
	// from the host's video config reply, nil until the first one
	@Published var hostOS: Int?
	// the in-stream bitrate pick, nil until made, 0 = host default; survives a reconnect, not a new session
	@Published var streamBitrate: Int?
	// a host reply older than our own change must not undo it
	var localChangeAt = Date.distantPast

	func reset() {
		resolutionX = 0
		resolutionY = 0
		bitrate = 0
		hostDefaultBitrate = 0
		constantFps = false
		output = "none"
		displayConfigs = []
		isBlocked = false
		hostOS = nil
		streamBitrate = nil
		localChangeAt = .distantPast
	}
}

class DataManager {
	static let model = SharedModel()
}

extension ParsecStatus {
	func readable(connecting: Bool = false) -> String {
		switch self {
		case WS_ERR_AUTH:               return String(localized: "Authentication failed")
		case WS_ERR_CONNECT:            return String(localized: "Can't reach Parsec")
		case WS_ERR_TEAM_DEACTIVATED:   return String(localized: "Team account deactivated")
		case NAT_ERR_PEER_PHASE:        return String(localized: "Couldn't reach the host")
		case NETWORK_ERR_BG_TIMEOUT:    return String(localized: "Timed out in the background")
		case NETWORK_ERR_UNSUPPORTED:   return String(localized: "Network not supported")
		case CONNECT_WRN_DECLINED:      return String(localized: "Host declined the connection")
		case CONNECT_WRN_NO_PERMISSION: return String(localized: "No permission to connect")
		case CONNECT_WRN_NO_ROOM:       return String(localized: "Host is full")
		case CONNECT_WRN_CANCELED:      return String(localized: "Connection canceled")
		case CONNECT_WRN_PEER_GONE:     return String(localized: "Host is offline")
		case HOST_WRN_KICKED:           return String(localized: "Kicked by the host")
		case HOST_WRN_SHUTDOWN:         return String(localized: "Host shut down")
		case SERVER_ERR_DISPLAY:        return String(localized: "Host has no display")
		case SERVER_ERR_RESOLUTION:     return String(localized: "Host resolution problem")
		case CAPTURE_ERR_INIT:          return String(localized: "Host capture failed")
		case CONNECT_WRN_APPROVAL:      return String(localized: "Host didn't approve the connection")
		case CONNECT_WRN_UNCONFIRMED:   return String(localized: "Confirm your Parsec account email first")
		case PARSEC_CONNECTING:         return String(localized: "Still connecting to the host")
		case PARSEC_NOT_RUNNING:        return String(localized: "Connection didn't start")
		case NETWORK_WRN_TIMEOUT:       return String(localized: "Network timed out")
		case NETWORK_ERR_SHUTDOWN:      return String(localized: "Host ended the connection")
		case NETWORK_ERR_INTERRUPTED:   return String(localized: "Connection was interrupted")
		case WS_ERR_GOING_AWAY, WS_ERR_CLOSE: return String(localized: "Parsec closed the connection")
		case WS_ERR_READ, WS_ERR_WRITE: return String(localized: "Lost the connection to Parsec")
		case NAT_ERR_NO_CANDIDATES:     return String(localized: "No network path to the host")
		case NAT_ERR_STUN_PHASE:        return String(localized: "Couldn't reach Parsec's network service")
		case SERVER_ERR_NO_USER:        return String(localized: "No one is signed in on the host")
		case SERVER_ERR_MAX_RESOLUTION: return String(localized: "Host can't stream at this resolution")
		case SERVER_ERR_CLIENT_GONE, SERVER_ERR_CLIENT_ABORT: return String(localized: "Host dropped the connection")
		default:
			os_log("%{public}@", "[status] no text for \(rawValue)")
			return connecting ? String(localized: "Couldn't connect (code \(rawValue))") : String(localized: "Disconnected (code \(rawValue))")
		}
	}

	var isPermanentFailure: Bool {
		switch self {
		case WS_ERR_AUTH, WS_ERR_TEAM_DEACTIVATED,
			 CONNECT_WRN_DECLINED, CONNECT_WRN_NO_PERMISSION, CONNECT_WRN_NO_ROOM,
			 CONNECT_WRN_CANCELED,
			 HOST_WRN_KICKED, HOST_WRN_SHUTDOWN,
			 NETWORK_ERR_UNSUPPORTED, SERVER_ERR_DISPLAY, SERVER_ERR_RESOLUTION,
			 CONNECT_WRN_UNCONFIRMED, SERVER_ERR_NO_USER, CONNECT_WRN_APPROVAL:
			return true
		default:
			return false
		}
	}
}
