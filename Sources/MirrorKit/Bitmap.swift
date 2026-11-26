import AppKit
import CoreGraphics
import Foundation

/// Simple RGBA8 bitmap with top-left origin, useful for pixel analysis and cropping.
public struct Bitmap {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8] // RGBA, 4 bytes per pixel, row-major from top

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    public init(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        self.init(width: w, height: h)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        pixels.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: cs, bitmapInfo: info) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
    }

    public init?(contentsOf path: URL) {
        guard let src = CGImageSourceCreateWithURL(path as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(cgImage: img)
    }

    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard x >= 0, y >= 0, x < width, y < height else { return (0, 0, 0, 0) }
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    public func isBackground(x: Int, y: Int, threshold: UInt8 = 20) -> Bool {
        let (r, g, b, a) = pixel(x: x, y: y)
        return a < 10 || (r < threshold && g < threshold && b < threshold)
    }

    /// Crop in top-left pixel coordinates. Rect is clamped to the bitmap bounds.
    public func cropped(to rect: CGRect) -> Bitmap {
        let x0 = max(0, min(width, Int(rect.minX.rounded())))
        let y0 = max(0, min(height, Int(rect.minY.rounded())))
        let x1 = max(x0, min(width, Int(rect.maxX.rounded())))
        let y1 = max(y0, min(height, Int(rect.maxY.rounded())))
        let w = x1 - x0, h = y1 - y0
        var out = Bitmap(width: max(1, w), height: max(1, h))
        for y in 0..<h {
            let src = ((y0 + y) * width + x0) * 4
            let dst = y * out.width * 4
            _ = out.pixels.withUnsafeMutableBufferPointer { p in
                pixels.withUnsafeBufferPointer { s in
                    memcpy(p.baseAddress! + dst, s.baseAddress! + src, w * 4)
                }
            }
        }
        return out
    }

    public func cgImage() -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    public func pngData() -> Data? {
        guard let img = cgImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: img)
        return rep.representation(using: .png, properties: [:])
    }
}

public func loadBitmap(_ url: URL) -> Bitmap? {
    return Bitmap(contentsOf: url)
}
