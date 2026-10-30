// Pane 的 App icon（1024）：黑白兩版，跟 Cinder / 漫畫的淺深成對同一套（漸層底＋半透明描邊）。
// 圖形是半開的兩片霧面玻璃窗格（摺疊機的兩半，內緣較高像朝你打開）。
// 淺色＝白底深色玻璃，深色＝黑底淺色玻璃，tinted 給系統上色。
// 另出圓角版 IconTransparent（淺/深兩張）給 App 內（登入頁、選單鈕、頭像佔位）用。
// 用法：swift scripts/make-icon.swift Pane/Assets.xcassets
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "."
let S: CGFloat = 1024
enum Style { case light, dark, tinted }

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

func render(_ style: Style) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
							   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
							   bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let ctx = NSGraphicsContext.current!.cgContext

	let light = style == .light
	let bg = NSGradient(colors: light ? [NSColor(white: 0.99, alpha: 1), NSColor(white: 0.86, alpha: 1)]
									  : [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.02, alpha: 1)])!
	bg.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -70)
	// 玻璃的顏色：淺底用黑、深底用白
	let ink: CGFloat = light ? 0.16 : 0.92

	// 兩片窗格：內緣（靠轉軸）高、外緣矮，像半開的摺疊機
	let cx = S / 2, cy = S * 0.51
	let gap = S * 0.024, w = S * 0.29, inner = S * 0.52, outer = S * 0.43
	let left = [CGPoint(x: cx - gap / 2 - w, y: cy + outer / 2), CGPoint(x: cx - gap / 2, y: cy + inner / 2),
				CGPoint(x: cx - gap / 2, y: cy - inner / 2), CGPoint(x: cx - gap / 2 - w, y: cy - outer / 2)]
	let right = left.map { CGPoint(x: 2 * cx - $0.x, y: $0.y) }
	// 淺色：深石板玻璃＋亮邊；深色：亮銀玻璃。後片（左）淡一些拉出前後
	let panes = light ? [(left, 0.55, 0.0), (right, 0.80, 0.0)] : [(left, 0.30, 0.0), (right, 0.55, 0.0)]
	for (pts, fill, stroke) in panes {
		let path = rounded(pts, radius: 40)
		ctx.addPath(path)
		ctx.setFillColor(NSColor(white: ink, alpha: fill).cgColor)
		ctx.fillPath()
		// 上緣一道淡淡的掃光
		ctx.saveGState()
		ctx.addPath(path)
		ctx.clip()
		let sheen = NSGradient(colors: [NSColor(white: 1, alpha: light ? 0.22 : 0.30), NSColor(white: 1, alpha: 0)])!
		sheen.draw(in: NSRect(x: cx - S / 2, y: cy, width: S, height: inner / 2), angle: -90)
		ctx.restoreGState()
		ctx.addPath(path)
		ctx.setStrokeColor(NSColor(white: 1, alpha: light ? 0.35 + stroke : 0.55 + stroke).cgColor)
		ctx.setLineWidth(5)
		ctx.strokePath()
	}

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

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }
func save(_ data: Data, _ path: String) { try! data.write(to: URL(fileURLWithPath: out + "/" + path)) }

let lightIcon = render(.light), darkIcon = render(.dark)
save(png(lightIcon), "AppIcon.appiconset/AppIcon.png")
save(png(darkIcon), "AppIcon.appiconset/AppIcon-dark.png")
save(png(render(.tinted)), "AppIcon.appiconset/AppIcon-tinted.png")
save(roundedCopy(lightIcon, size: 384), "IconTransparent.imageset/icon.png")
save(roundedCopy(darkIcon, size: 384), "IconTransparent.imageset/icon-dark.png")
print("ok")
