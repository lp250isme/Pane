import CoreGraphics

// ParsecClientPollFrame scales frames to the ParsecClientSetDimensions size without keeping aspect,
// and in points, so the Metal path got a stretched, low-res picture on any non-16:9 screen.
// Metal instead hands the SDK the picture's own rect (host aspect, in pixels) and mouse coords are
// mapped between view points and that rect.
struct PictureFit: Equatable {
	var origin: CGPoint = .zero   // picture top-left in view points
	var scale: CGFloat = 1        // SDK units per view point
	var dims: CGSize              // what the SDK is given

	init(identity view: CGSize) {
		dims = view
	}

	init(view: CGSize, host: CGSize, screenScale: CGFloat) {
		guard host.width > 0, host.height > 0, view.width > 0, view.height > 0, screenScale > 0 else {
			dims = view
			return
		}
		let fit = min(view.width / host.width, view.height / host.height)
		let picture = CGSize(width: host.width * fit, height: host.height * fit)
		origin = CGPoint(x: (view.width - picture.width) / 2, y: (view.height - picture.height) / 2)
		// sharp on the screen, but never past the host's own resolution
		scale = min(screenScale, host.width / picture.width)
		dims = CGSize(width: (picture.width * scale).rounded(), height: (picture.height * scale).rounded())
	}

	func toSDK(_ p: CGPoint) -> CGPoint {
		CGPoint(x: min(max(0, (p.x - origin.x) * scale), dims.width),
				y: min(max(0, (p.y - origin.y) * scale), dims.height))
	}

	func fromSDK(_ p: CGPoint) -> CGPoint {
		CGPoint(x: p.x / scale + origin.x, y: p.y / scale + origin.y)
	}
}
