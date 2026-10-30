import CoreGraphics
import Foundation
import Testing
@testable import PaneCore

// MARK: - Host replies: hosts differ in which keys they send

@Suite struct UserDataDecodingTests {
	let d = JSONDecoder()

	@Test func 缺欄位的回覆仍能解出有的欄位() throws {
		let sparse = try d.decode(ParsecUserDataVideoConfig.self, from: Data(#"{"video":[{"encoderMaxBitrate":30,"output":"\\\\.\\DISPLAY2"}]}"#.utf8))
		#expect(sparse.video.count == 1)
		#expect(sparse.video[0].encoderMaxBitrate == 30)
		#expect(sparse.video[0].output == #"\\.\DISPLAY2"#)
		#expect(sparse.video[0].resolutionX == 0 && sparse.video[0].fullFPS == false)
	}

	@Test func 沒有output等於自動而不是丟錯() throws {
		let v = try d.decode(ParsecUserDataVideo.self, from: Data(#"{"resolutionX":3840}"#.utf8))
		#expect(v.output == "none" && v.resolutionX == 3840)
	}

	@Test func 送出的設定來回編解碼不掉欄位() throws {
		var cfg = ParsecUserDataVideoConfig()
		cfg.video[0].output = "abc"
		cfg.video[0].encoderMaxBitrate = 20
		let back = try d.decode(ParsecUserDataVideoConfig.self, from: try JSONEncoder().encode(cfg))
		#expect(back.video.count == 3 && back.video[0].output == "abc" && back.video[0].encoderMaxBitrate == 20)
	}

	@Test func 螢幕清單的空欄位補空字串() throws {
		let displays = try d.decode([ParsecDisplayConfig].self, from: Data(#"[{"name":"A","id":"1"},{}]"#.utf8))
		#expect(displays.count == 2 && displays[0].adapterName == "" && displays[1].id == "")
	}

	// Mac host (parsecd) sends hostOS 2 in every video entry
	@Test func 讀得到主機作業系統() throws {
		let cfg = try d.decode(ParsecUserDataVideoConfig.self, from: Data(#"{"video":[{"hostOS":2,"output":"1a2b"}]}"#.utf8))
		#expect(cfg.video[0].hostOS == macHostOS)
	}
}

// MARK: - The size asked of the host

@Suite struct RequestedResolutionTests {
	@Test func Mac主機一律送預設0x0() {
		let r = requestedResolution(hostOS: macHostOS, picked: (2670, 1502))
		#expect(r.x == 0 && r.y == 0)
	}

	@Test func 其他主機照使用者選的送() {
		let r = requestedResolution(hostOS: 0, picked: (1920, 1080))
		#expect(r.x == 1920 && r.y == 1080)
	}

	// before the first reply the OS is unknown: send the pick (connect itself already asked for 0x0)
	@Test func 還不知道主機作業系統時照選的送() {
		let r = requestedResolution(hostOS: nil, picked: (1280, 720))
		#expect(r.x == 1280 && r.y == 720)
	}
}

// MARK: - Cursor through a resize (rotate, fold)

@Suite struct CarryCursorTests {
	let host = CGSize(width: 1920, height: 1080)

	@Test func 畫面中心換尺寸後仍在中心() {
		let p = carryCursor(CGPoint(x: 400, y: 300), from: CGSize(width: 800, height: 600), to: CGSize(width: 600, height: 800), host: host)
		#expect(abs(p.x - 300) < 0.01 && abs(p.y - 400) < 0.01)
	}

	// 800x600 letterboxes 16:9 to 800x450 starting at y=75; 1600x900 fills exactly
	@Test func 黑邊內的點對到同一個主機座標() {
		let p = carryCursor(CGPoint(x: 0, y: 75), from: CGSize(width: 800, height: 600), to: CGSize(width: 1600, height: 900), host: host)
		#expect(abs(p.x) < 0.01 && abs(p.y) < 0.01)
	}

	@Test func 結果夾在新尺寸內() {
		let p = carryCursor(CGPoint(x: 800, y: 600), from: CGSize(width: 800, height: 600), to: CGSize(width: 400, height: 300), host: host)
		#expect(p.x <= 400 && p.y <= 300 && p.x >= 0 && p.y >= 0)
	}

	@Test func 還沒有主機尺寸時等比例縮放() {
		let p = carryCursor(CGPoint(x: 100, y: 50), from: CGSize(width: 200, height: 100), to: CGSize(width: 400, height: 300), host: .zero)
		#expect(p.x == 200 && p.y == 150)
	}
}

// MARK: - Direct touch's held-back left press

@Suite struct DirectClickTests {
	@Test func 快速點一下仍是一次完整點擊() {
		var c = DirectClick()
		c.begin()
		let (press, release) = c.lift()
		#expect(press && release)
	}

	@Test func 第二指在等待中落下就不送左鍵() {
		var c = DirectClick()
		c.begin()
		c.cancel()
		let (press, release) = c.lift()
		#expect(!press && !release)
	}

	@Test func 等待結束才送按下且只送一次() {
		var c = DirectClick()
		c.begin()
		let first = c.press()
		let second = c.press()
		#expect(first && !second)
		let (press, release) = c.lift()
		#expect(!press && release)
	}

	// a two-finger gesture that starts after the press went out still has to let go of the button
	@Test func 已按下後第二指落下仍會放開() {
		var c = DirectClick()
		c.begin()
		_ = c.press()
		c.cancel()
		let (press, release) = c.lift()
		#expect(!press && release)
	}

	@Test func 沒開始過的抬起什麼都不送() {
		var c = DirectClick()
		let (press, release) = c.lift()
		#expect(!press && !release)
	}
}

// MARK: - Trackpad below the picture

@Suite struct TrackpadTests {
	@Test func 點擊依手指數() {
		#expect(trackpadTap(fingers: 1) == .leftClick)
		#expect(trackpadTap(fingers: 2) == .rightClick)
		#expect(trackpadTap(fingers: 3) == .toggleKeyboard)
		#expect(trackpadTap(fingers: 4) == nil)
	}

	@Test func 滑動要超過門檻才算且取主要方向() {
		#expect(trackpadSwipe(CGVector(dx: 30, dy: 5), threshold: 60) == nil)
		#expect(trackpadSwipe(CGVector(dx: -80, dy: 20), threshold: 60) == .swipeLeft)
		#expect(trackpadSwipe(CGVector(dx: 10, dy: -90), threshold: 60) == .swipeUp)
		#expect(trackpadSwipe(CGVector(dx: 70, dy: 75), threshold: 60) == .swipeDown)
	}

	@Test func 四指開合() {
		#expect(trackpadPinch(spreadRatio: 0.5) == .pinch)
		#expect(trackpadPinch(spreadRatio: 1.8) == .spread)
		#expect(trackpadPinch(spreadRatio: 1.0) == nil)
	}

	@Test func Mac主機對到Mac的快捷鍵() {
		#expect(trackpadKeys(.swipeUp, hostOS: macHostOS) == [HIDKey.ctrl, HIDKey.up])
		#expect(trackpadKeys(.swipeDown, hostOS: macHostOS) == [HIDKey.ctrl, HIDKey.down])
		// swiping left brings in the Space on the right, like a Mac trackpad
		#expect(trackpadKeys(.swipeLeft, hostOS: macHostOS) == [HIDKey.ctrl, HIDKey.right])
		#expect(trackpadKeys(.spread, hostOS: macHostOS) == [HIDKey.f11])
	}

	@Test func 其他主機對到Windows的快捷鍵() {
		#expect(trackpadKeys(.swipeUp, hostOS: 0) == [HIDKey.gui, HIDKey.tab])
		#expect(trackpadKeys(.swipeDown, hostOS: 0) == [HIDKey.gui, HIDKey.d])
		#expect(trackpadKeys(.swipeRight, hostOS: nil) == [HIDKey.ctrl, HIDKey.gui, HIDKey.left])
	}

	@Test func 直向時畫面貼頂端下方留給觸控板() {
		let r = pictureAboveTrackpad(in: CGRect(x: 0, y: 0, width: 400, height: 860), topInset: 50, host: CGSize(width: 1920, height: 1080), minTrackpad: 120)
		#expect(r == CGRect(x: 0, y: 50, width: 400, height: 225))
	}

	@Test func 橫向或空間不夠時不切() {
		#expect(pictureAboveTrackpad(in: CGRect(x: 0, y: 0, width: 860, height: 400), topInset: 0, host: CGSize(width: 1920, height: 1080), minTrackpad: 120) == nil)
		// a portrait host fills a portrait screen: nothing left for a trackpad
		#expect(pictureAboveTrackpad(in: CGRect(x: 0, y: 0, width: 400, height: 860), topInset: 50, host: CGSize(width: 858, height: 2048), minTrackpad: 120) == nil)
		#expect(pictureAboveTrackpad(in: CGRect(x: 0, y: 0, width: 400, height: 860), topInset: 0, host: .zero, minTrackpad: 120) == nil)
	}
}
