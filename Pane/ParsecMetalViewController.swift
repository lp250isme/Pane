import UIKit
import MetalKit

class ParsecMetalViewController: ParsecPlayground {

	var metalView: MetalStreamView!
	let metalRenderer: ParsecMetalRenderer?
	let updateImage: () -> Void

	var renderView: UIView { metalView }

	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.updateImage = updateImage
		metalRenderer = MTLCreateSystemDefaultDevice().flatMap { ParsecMetalRenderer($0) }
	}

	public func viewDidLoad() {
		guard let renderer = metalRenderer else { return }
		metalView = MetalStreamView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height), renderer: renderer, fps: SettingsHandler.preferredFramesPerSecond, onTick: updateImage)
		ParsecBackgroundManager.shared.glkViewController = metalView
	}

	func cleanUp() {
		metalView?.isPaused = true
		metalRenderer?.reset()
	}

	func updateSize(width: CGFloat, height: CGFloat) {
		metalView.frame.size.width = width
		metalView.frame.size.height = height
	}
}

final class MetalStreamView: UIView, RenderLoop {
	override class var layerClass: AnyClass { CAMetalLayer.self }
	private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
	private let renderer: ParsecMetalRenderer
	private var link: CADisplayLink?
	private var lastSize = CGSize.zero
	private var lastScale: CGFloat = 0
	private var lastPixels = CGSize.zero

	// the frames go out on the renderer's thread; the display link only keeps the cursor and layout current
	// and asks the screen for its full refresh rate
	init(frame: CGRect, renderer: ParsecMetalRenderer, fps: Int, onTick: @escaping () -> Void) {
		self.renderer = renderer
		super.init(frame: frame)
		backgroundColor = .black
		contentScaleFactor = UIScreen.main.scale
		metalLayer.device = renderer.device
		metalLayer.pixelFormat = .bgra8Unorm
		metalLayer.framebufferOnly = true
		metalLayer.isOpaque = true
		renderer.minInterval = 0.75 / Double(fps > 0 ? fps : UIScreen.main.maximumFramesPerSecond)
		let link = CADisplayLink(target: LinkTarget(onTick), selector: #selector(LinkTarget.fire))
		link.preferredFramesPerSecond = fps
		link.add(to: .main, forMode: .common)
		self.link = link
		renderer.start(metalLayer)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		link?.invalidate()
		renderer.stop()
	}

	var isPaused = false {
		didSet {
			guard isPaused != oldValue else { return }
			link?.isPaused = isPaused
			if isPaused {
				renderer.stop()
			} else {
				renderer.start(metalLayer)
			}
		}
	}

	// zoom renders at a higher scale
	override var contentScaleFactor: CGFloat {
		didSet { setNeedsLayout() }
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		// height too: fold / tabletop changes can keep the width
		let viewSize = frame.size
		if abs(viewSize.width - lastSize.width) > 0.1 || abs(viewSize.height - lastSize.height) > 0.1 || abs(contentScaleFactor - lastScale) > 0.01 {
			CParsec.setFrame(viewSize.width, viewSize.height, contentScaleFactor)
			lastSize = viewSize
			lastScale = contentScaleFactor
		}
		let size = CGSize(width: (bounds.width * contentScaleFactor).rounded(), height: (bounds.height * contentScaleFactor).rounded())
		if size != lastPixels {
			lastPixels = size
			renderer.resize(size)
		}
	}
}

private final class LinkTarget: NSObject {
	let tick: () -> Void
	init(_ tick: @escaping () -> Void) { self.tick = tick }
	@objc func fire() { tick() }
}
