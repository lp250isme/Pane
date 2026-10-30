// Pane 的 App icon（1024）：跟 Reel / Zky 同一套（暗底漸層＋右上橘光暈＋半透明白描邊），
// 圖形是半開的兩片霧面玻璃窗格（摺疊機的兩半，內緣較高像朝你打開）加一個橘色游標＝遙控電腦。
// 另出一張圓角版 IconTransparent 給 App 內（登入頁、選單鈕、頭像佔位）用。
// 用法：swift scripts/make-icon.swift OpenParsec/Assets.xcassets
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "."
let S: CGFloat = 1024
let accent = NSColor(red: 1.0, green: 0.478, blue: 0.09, alpha: 1)

// 多邊形每個角用 arc 修圓
func rounded(_ pts: [CGPoint], radius r: CGFloat) -> CGPath {
	let p = CGMutablePath()
	let n = pts.count
	p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
	for i in 0..<n {
		p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: r)
	}
	p.closeSubpath()
	return p
}

func render(tinted: Bool) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
							   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
							   bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let ctx = NSGraphicsContext.current!.cgContext

	let bg = NSGradient(colors: tinted ? [NSColor(white: 0.12, alpha: 1), NSColor(white: 0.02, alpha: 1)]
									   : [NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1), NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)])!
	bg.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -70)
	if !tinted {
		let glow = NSGradient(colors: [accent.withAlphaComponent(0.32), accent.withAlphaComponent(0)])!
		glow.draw(fromCenter: NSPoint(x: S * 0.78, y: S * 0.82), radius: 0, toCenter: NSPoint(x: S * 0.78, y: S * 0.82), radius: S * 0.6, options: [])
	}

	// 兩片窗格：內緣（靠轉軸）高、外緣矮，像半開的摺疊機
	let cx = S / 2, cy = S * 0.51
	let gap = S * 0.024, w = S * 0.29, inner = S * 0.52, outer = S * 0.43
	let left = [CGPoint(x: cx - gap / 2 - w, y: cy + outer / 2), CGPoint(x: cx - gap / 2, y: cy + inner / 2),
				CGPoint(x: cx - gap / 2, y: cy - inner / 2), CGPoint(x: cx - gap / 2 - w, y: cy - outer / 2)]
	let right = left.map { CGPoint(x: 2 * cx - $0.x, y: $0.y) }
	for (pts, fill, stroke) in [(left, 0.09, 0.28), (right, 0.17, 0.42)] {
		let path = rounded(pts, radius: 40)
		ctx.addPath(path)
		ctx.setFillColor(NSColor(white: 1, alpha: fill).cgColor)
		ctx.fillPath()
		// 上緣一道淡淡的掃光
		ctx.saveGState()
		ctx.addPath(path)
		ctx.clip()
		let sheen = NSGradient(colors: [NSColor(white: 1, alpha: 0.14), NSColor(white: 1, alpha: 0)])!
		sheen.draw(in: NSRect(x: cx - S / 2, y: cy, width: S, height: inner / 2), angle: -90)
		ctx.restoreGState()
		ctx.addPath(path)
		ctx.setStrokeColor(NSColor(white: 1, alpha: stroke).cgColor)
		ctx.setLineWidth(4)
		ctx.strokePath()
	}

	// 游標：尖端朝左上，壓在右窗格上
	let tip = CGPoint(x: S * 0.535, y: S * 0.60), h = S * 0.33
	let unit: [(CGFloat, CGFloat)] = [(0, 0), (0, -0.80), (0.21, -0.62), (0.34, -0.93), (0.47, -0.87), (0.34, -0.57), (0.60, -0.57)]
	let arrow = rounded(unit.map { CGPoint(x: tip.x + $0.0 * h, y: tip.y + $0.1 * h) }, radius: 12)
	ctx.saveGState()
	ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(white: 0, alpha: 0.55).cgColor)
	ctx.addPath(arrow)
	ctx.setFillColor((tinted ? NSColor(white: 1, alpha: 0.85) : accent).cgColor)
	ctx.fillPath()
	ctx.restoreGState()
	ctx.addPath(arrow)
	ctx.setStrokeColor(NSColor(white: 1, alpha: 0.55).cgColor)
	ctx.setLineWidth(5)
	ctx.strokePath()

	NSGraphicsContext.restoreGraphicsState()
	return rep
}

// App 內用：同一張圖切 iOS 圓角，四角透明
func roundedCopy(_ src: NSBitmapImageRep, size: CGFloat) -> Data {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
							   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
							   bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let r = NSRect(x: 0, y: 0, width: size, height: size)
	NSBezierPath(roundedRect: r, xRadius: size * 0.2237, yRadius: size * 0.2237).addClip()
	src.draw(in: r)
	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

let icon = render(tinted: false)
let png = icon.representation(using: .png, properties: [:])!
// 一般與深色同一張（本來就是暗底）；tinted 去掉色彩讓系統上色
try! png.write(to: URL(fileURLWithPath: out + "/AppIcon.appiconset/AppIcon.png"))
try! png.write(to: URL(fileURLWithPath: out + "/AppIcon.appiconset/AppIcon-dark.png"))
try! render(tinted: true).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/AppIcon.appiconset/AppIcon-tinted.png"))
try! roundedCopy(icon, size: 384).write(to: URL(fileURLWithPath: out + "/IconTransparent.imageset/icon.png"))
print("ok")
