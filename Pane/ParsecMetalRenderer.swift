import MetalKit
import ParsecSDK
import os

private let nv12Source = """
#include <metal_stdlib>
using namespace metal;
struct VOut { float4 pos [[position]]; float2 uv; };
vertex VOut vs(uint vid [[vertex_id]]) {
	float2 p = float2(float(vid & 1), float(vid >> 1));
	VOut o;
	o.pos = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
	o.uv = p;
	return o;
}
fragment float4 fs(VOut in [[stage_in]], texture2d<float> yt [[texture(0)]], texture2d<float> ct [[texture(1)]], sampler s [[sampler(0)]]) {
	float y = (yt.sample(s, in.uv).r - 0.0625) * 1.164;
	float2 c = ct.sample(s, in.uv).rg - 0.5;
	return float4(y + 1.793 * c.y, y - 0.213 * c.x - 0.533 * c.y, y + 2.112 * c.x, 1.0);
}
"""

private let frameCallback: ParsecFrameCallback = { frame, image, opaque in
	guard let frame = frame, let image = image, let opaque = opaque else { return }
	Unmanaged<ParsecMetalRenderer>.fromOpaque(opaque).takeUnretainedValue().upload(frame.pointee, image)
}

extension ParsecFrame {
	var isWholeNV12: Bool {
		let w = Int(width), h = Int(height), stride = Int(fullWidth), rows = Int(fullHeight)
		return format == FORMAT_NV12 && w > 0 && h > 0 && stride >= w && rows >= h && Int(size) >= stride * rows + stride * ((h + 1) / 2)
	}
}

// Frames are waited for, uploaded and shown on a thread of their own: the main thread stays free for touches,
// and a frame goes to the screen the moment it arrives instead of at the next display tick.
class ParsecMetalRenderer: NSObject {
	private let queue: MTLCommandQueue
	private let pipeline: MTLRenderPipelineState
	private let sampler: MTLSamplerState
	// two in flight at most: while an upload runs, only the slot shown last can still be read by the GPU
	private let inFlight = DispatchSemaphore(value: 2)
	private var planes: [(y: MTLTexture, c: MTLTexture)?] = [nil, nil, nil]
	private var current = -1
	private var lastShownSlot = -1
	private var frameSize = CGSize.zero
	private var fresh = false

	private let lock = NSLock()
	private var running = false
	private var redraw = false
	private var thread: Thread?
	private let stopped = DispatchSemaphore(value: 0)
	private var layer: CAMetalLayer?
	private var size: CGSize?
	// the frame rate setting or the screen's rate: a host sending faster would only queue drawables
	var minInterval: CFTimeInterval = 0

	var device: MTLDevice { queue.device }

	init?(_ device: MTLDevice) {
		guard let queue = device.makeCommandQueue() else { return nil }
		let pipeline: MTLRenderPipelineState
		do {
			let library = try device.makeLibrary(source: nv12Source, options: nil)
			let desc = MTLRenderPipelineDescriptor()
			desc.vertexFunction = library.makeFunction(name: "vs")
			desc.fragmentFunction = library.makeFunction(name: "fs")
			desc.colorAttachments[0].pixelFormat = .bgra8Unorm
			pipeline = try device.makeRenderPipelineState(descriptor: desc)
		} catch {
			os_log("%{public}@", log: sdkLog, type: .error, "metal: \(error)")
			return nil
		}
		let sd = MTLSamplerDescriptor()
		sd.minFilter = .linear
		sd.magFilter = .linear
		guard let sampler = device.makeSamplerState(descriptor: sd) else { return nil }
		self.queue = queue
		self.pipeline = pipeline
		self.sampler = sampler
		super.init()
	}

	// only while stopped
	func reset() {
		planes = [nil, nil, nil]
		current = -1
		lastShownSlot = -1
	}

	func start(_ layer: CAMetalLayer) {
		guard thread == nil else { return }
		self.layer = layer
		lock.lock()
		running = true
		redraw = true
		lock.unlock()
		let t = Thread { [self] in loop() }
		t.name = "pane.render"
		t.qualityOfService = .userInteractive
		thread = t
		t.start()
	}

	// waits for the thread to finish, so Picture in Picture can poll frames right after
	func stop() {
		guard thread != nil else { return }
		lock.lock()
		running = false
		lock.unlock()
		stopped.wait()
		thread = nil
	}

	// the drawable size is changed on the render thread, between drawables; the last frame is shown again at it
	func resize(_ px: CGSize) {
		lock.lock()
		size = px
		redraw = true
		lock.unlock()
	}

	private func loop() {
		let me = Unmanaged.passUnretained(self).toOpaque()
		var lastShown: CFTimeInterval = 0
		var pending = false
		// no drawable last time: try again at the normal poll pace, not in a tight loop
		var missed = false
		var shown = 0
		var sampleAt = CACurrentMediaTime()
		// a hot phone shows at most 60 frames a second
		var hot = false
		while true {
			lock.lock()
			let go = running
			if redraw { pending = true }
			redraw = false
			let px = size
			size = nil
			lock.unlock()
			guard go else { break }
			if let px = px { layer?.drawableSize = px }

			inFlight.wait()
			let polledAt = CACurrentMediaTime()
			let gap = hot ? max(minInterval, 0.75 / 60) : minInterval
			// a frame held back by the gap goes out as soon as the gap is over, unless a newer one comes first
			let wait = pending && !missed ? UInt32(max(1, min(16, (gap - (polledAt - lastShown)) * 1000))) : 16
			let status = CParsec.pollFrame(timeout: wait, callback: frameCallback, opaque: me)
			if fresh { pending = true }
			fresh = false
			let now = CACurrentMediaTime()
			if pending && now - lastShown >= gap {
				if show() {
					pending = false
					missed = false
					lastShown = now
					shown += 1
				} else {
					// nothing to show before the first frame; a missing drawable is tried again
					pending = current >= 0
					missed = pending
					inFlight.signal()
				}
			} else {
				inFlight.signal()
			}
			// not connected: the poll returns at once, don't spin
			if status != PARSEC_OK && wait >= 16 && now - polledAt < 0.002 {
				usleep(8_000)
			}

			let elapsed = now - sampleAt
			if elapsed >= 1 {
				let rate = elapsed <= 2 ? Double(shown) / elapsed : nil
				shown = 0
				sampleAt = now
				let warm = ProcessInfo.processInfo.thermalState.rawValue >= 2
				if warm != hot {
					hot = warm
					diag("[render] \(hot ? "hot, at most 60 fps" : "cooled down, full rate")")
				}
				if let rate = rate {
					DispatchQueue.main.async { CParsec.drawRate = rate }
				}
			}
		}
		stopped.signal()
	}

	fileprivate func upload(_ f: ParsecFrame, _ image: UnsafeRawPointer) {
		let w = Int(f.width), h = Int(f.height), stride = Int(f.fullWidth), rows = Int(f.fullHeight)
		guard f.isWholeNV12 else { return }
		var slot = (current + 1) % planes.count
		if slot == lastShownSlot { slot = (slot + 1) % planes.count }
		if planes[slot]?.y.width != w || planes[slot]?.y.height != h {
			planes[slot] = makePlanes(w, h)
		}
		guard let p = planes[slot] else { return }
		p.y.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: image, bytesPerRow: stride)
		p.c.replace(region: MTLRegionMake2D(0, 0, (w + 1) / 2, (h + 1) / 2), mipmapLevel: 0, withBytes: image + stride * rows, bytesPerRow: stride)
		current = slot
		frameSize = CGSize(width: w, height: h)
		fresh = true
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.feedFrame(f, image)
		}
	}

	private func makePlanes(_ w: Int, _ h: Int) -> (y: MTLTexture, c: MTLTexture)? {
		let yd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
		let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: (w + 1) / 2, height: (h + 1) / 2, mipmapped: false)
		guard let y = queue.device.makeTexture(descriptor: yd), let c = queue.device.makeTexture(descriptor: cd) else { return nil }
		return (y, c)
	}

	// on success the semaphore is signalled when the GPU is done
	private func show() -> Bool {
		lock.lock()
		let go = running
		lock.unlock()
		guard go, current >= 0, let p = planes[current], let drawable = layer?.nextDrawable(), let cb = queue.makeCommandBuffer() else { return false }
		let pass = MTLRenderPassDescriptor()
		pass.colorAttachments[0].texture = drawable.texture
		pass.colorAttachments[0].loadAction = .clear
		pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
		pass.colorAttachments[0].storeAction = .store
		guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return false }
		let dw = CGFloat(drawable.texture.width), dh = CGFloat(drawable.texture.height)
		let s = min(dw / frameSize.width, dh / frameSize.height)
		let w = frameSize.width * s
		let h = frameSize.height * s
		enc.setViewport(MTLViewport(originX: Double((dw - w) / 2), originY: Double((dh - h) / 2), width: Double(w), height: Double(h), znear: 0, zfar: 1))
		enc.setRenderPipelineState(pipeline)
		enc.setFragmentTexture(p.y, index: 0)
		enc.setFragmentTexture(p.c, index: 1)
		enc.setFragmentSamplerState(sampler, index: 0)
		enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		enc.endEncoding()
		cb.present(drawable)
		lastShownSlot = current
		let sem = inFlight
		cb.addCompletedHandler { _ in sem.signal() }
		cb.commit()
		return true
	}
}
