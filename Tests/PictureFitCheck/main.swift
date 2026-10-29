// Run: swiftc OpenParsec/PictureFit.swift Tests/PictureFitCheck/main.swift -o /tmp/picturefit && /tmp/picturefit
import CoreGraphics

func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.6) -> Bool { abs(a - b) <= tol }

// iPhone Duo inner screen, landscape, streaming a 16:9 Mac: letterboxed, full pixel density, 16:9 dims
let duo = PictureFit(view: CGSize(width: 951, height: 669), host: CGSize(width: 3840, height: 2160), screenScale: 2.807)
assert(near(duo.origin.x, 0) && near(duo.origin.y, 67.03, 0.05), "picture centered vertically: \(duo.origin)")
assert(duo.dims == CGSize(width: 2669, height: 1502), "pixel dims: \(duo.dims)")
assert(abs(duo.dims.width / duo.dims.height - 16.0 / 9.0) < 0.002, "host aspect kept")

// view center lands on the host center; the picture's corners land on the SDK corners
let c = duo.toSDK(CGPoint(x: 475.5, y: 334.5))
assert(near(c.x, duo.dims.width / 2, 1) && near(c.y, duo.dims.height / 2, 1), "center: \(c)")
assert(duo.toSDK(CGPoint(x: 0, y: 67.03)) == .zero || near(duo.toSDK(CGPoint(x: 0, y: 67.03)).y, 0, 0.2))
// touches in the black bars clamp to the picture edge
assert(duo.toSDK(CGPoint(x: 10, y: 5)).y == 0)
assert(duo.toSDK(CGPoint(x: 10, y: 668)).y == duo.dims.height)

// SDK cursor positions come back to the same view point
for p in [CGPoint(x: 100, y: 200), CGPoint(x: 950, y: 600), CGPoint(x: 0, y: 70)] {
	let back = duo.fromSDK(duo.toSDK(p))
	assert(near(back.x, p.x, 0.01) && near(back.y, p.y, 0.01), "round trip \(p) -> \(back)")
}

// a host smaller than the screen never asks for more pixels than it sends
let small = PictureFit(view: CGSize(width: 951, height: 669), host: CGSize(width: 1280, height: 720), screenScale: 3)
assert(near(small.dims.width, 1280, 1) && near(small.dims.height, 720, 1), "capped at host: \(small.dims)")

// host aspect taller than the view: pillarbox on the sides
let tall = PictureFit(view: CGSize(width: 951, height: 669), host: CGSize(width: 1920, height: 1920), screenScale: 3)
assert(near(tall.origin.y, 0) && near(tall.origin.x, (951 - 669) / 2), "pillarbox: \(tall.origin)")

// before the host size is known the mapping is the identity
let unknown = PictureFit(view: CGSize(width: 951, height: 669), host: .zero, screenScale: 3)
assert(unknown == PictureFit(identity: CGSize(width: 951, height: 669)))
assert(unknown.toSDK(CGPoint(x: 12, y: 34)) == CGPoint(x: 12, y: 34))

print("PictureFit checks passed")
