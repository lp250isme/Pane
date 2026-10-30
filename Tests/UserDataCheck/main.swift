// Run: swiftc OpenParsec/ParsecUserData.swift Tests/UserDataCheck/main.swift -o /tmp/userdata && /tmp/userdata
import Foundation

let d = JSONDecoder()

// a reply missing keys still decodes, with the keys it has
let sparse = try! d.decode(ParsecUserDataVideoConfig.self, from: Data(#"{"video":[{"encoderMaxBitrate":30,"output":"\\\\.\\DISPLAY2"}]}"#.utf8))
assert(sparse.video.count == 1 && sparse.video[0].encoderMaxBitrate == 30 && sparse.video[0].output == #"\\.\DISPLAY2"#)
assert(sparse.video[0].resolutionX == 0 && sparse.video[0].fullFPS == false)

// no output key means Auto, not a throw
let noOutput = try! d.decode(ParsecUserDataVideo.self, from: Data(#"{"resolutionX":3840}"#.utf8))
assert(noOutput.output == "none" && noOutput.resolutionX == 3840)

// what we send still round-trips with every key
var cfg = ParsecUserDataVideoConfig()
cfg.video[0].output = "abc"
cfg.video[0].encoderMaxBitrate = 20
let back = try! d.decode(ParsecUserDataVideoConfig.self, from: try! JSONEncoder().encode(cfg))
assert(back.video.count == 3 && back.video[0].output == "abc" && back.video[0].encoderMaxBitrate == 20)

let displays = try! d.decode([ParsecDisplayConfig].self, from: Data(#"[{"name":"A","id":"1"},{}]"#.utf8))
assert(displays.count == 2 && displays[0].adapterName == "" && displays[1].id == "")

print("UserData checks passed")
