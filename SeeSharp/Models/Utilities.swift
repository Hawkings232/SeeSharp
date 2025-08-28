//
//  Utilities.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 6/1/25.
//

import Foundation
import CoreImage

struct ApplicationError : Identifiable
{
    let id = UUID()
    let underlyingError: Error
    
    var localizedDescription: String {
        return underlyingError.localizedDescription
    }
    
    init(err underlyingError: Error)
    {
        self.underlyingError = underlyingError
    }
}

struct Utilities
{
    static var ciContext: CIContext = CIContext()
    
    /// Resize a pixel buffer to the model's expected 256×256 BGRA format.
    static func resize(buffer: CVPixelBuffer,
                width: Int = 256,
                height: Int = 256) -> CVPixelBuffer?
    {
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let ciImage = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: colorSpace])
        
        let sx = CGFloat(width) / ciImage.extent.width
        let sy = CGFloat(height) / ciImage.extent.height
        let scaled = ciImage.transformed(by: .init(scaleX: sx, y: sy))

        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
        ]

        CVPixelBufferCreate(kCFAllocatorDefault,
                            width, height,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary,
                            &out)
        guard let dest = out else {
            return nil
        }

        ciContext.render(scaled, to: dest, bounds: scaled.extent, colorSpace: colorSpace)

        return dest
        
//        let ciImage = CIImage(cvPixelBuffer: buffer)
//        let sx = CGFloat(width)  / ciImage.extent.width
//        let sy = CGFloat(height) / ciImage.extent.height
//        let scaled = ciImage.transformed(by: .init(scaleX: sx, y: sy))
//
//        var out: CVPixelBuffer?
//        let attrs: [CFString: Any] = [
//            kCVPixelBufferCGImageCompatibilityKey:         true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
//            kCVPixelBufferPixelFormatTypeKey:              Int(kCVPixelFormatType_32BGRA)
//        ]
//        
//        CVPixelBufferCreate(kCFAllocatorDefault,
//                            width, height,
//                            kCVPixelFormatType_32BGRA,
//                            attrs as CFDictionary,
//                            &out)
//        guard let dest = out else {
//            return nil
//        }
//        
//        ciContext.render(scaled, to: dest)
//        return dest
    }
    
    static func rotate90(buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ci = CIImage(cvPixelBuffer: buffer)
                  .oriented(.right)

        let w = Int(ci.extent.width)
        let h = Int(ci.extent.height)
        var rotated: CVPixelBuffer?
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferCreate(nil,
                            w, h,
                            pixelFormat,
                            nil,
                            &rotated)
        
        guard let out = rotated else { return nil }
        ciContext.render(ci, to: out)
        return out
    }
    
    static func cropPixelBuffer(from pixelBuffer : CVPixelBuffer, to rect: CGRect, context: CIContext = CIContext()) -> CVPixelBuffer? {
        let pixelBufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let ciCropRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(pixelBufferHeight) - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: ciCropRect)
        
        let translated = ciImage.transformed(by: CGAffineTransform(translationX: -ciCropRect.origin.x, y: -ciCropRect.origin.y))

        let finalImage = translated.cropped(to: CGRect(origin: .zero, size: CGSize(width: rect.width, height: rect.height)))

        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: Int(rect.width),
            kCVPixelBufferHeightKey: Int(rect.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        var croppedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            Int(rect.width),
            Int(rect.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &croppedBuffer
        )

        guard status == kCVReturnSuccess, let buffer = croppedBuffer else {
            return nil
        }

        context.render(finalImage, to: buffer)
        return buffer
    }

    
    static func cgImageToPixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }

    
    /// Pads a smaller CVPixelBuffer (e.g., 192x80) into a 256x256 buffer with black background.
    /// Returns both the padded buffer and the size of the original tile (for cropping later).
    static func paddedTile(from pixelBuffer: CVPixelBuffer, context: CIContext) -> (CVPixelBuffer, CGSize)? {
        let tileWidth = CVPixelBufferGetWidth(pixelBuffer)
        let tileHeight = CVPixelBufferGetHeight(pixelBuffer)

        guard tileWidth < 256 || tileHeight < 256 else { return (pixelBuffer, CGSize(width: tileWidth, height: tileHeight)) }

        let inputCI = CIImage(cvPixelBuffer: pixelBuffer)
        let paddedRect = CGRect(x: 0, y: 0, width: 256, height: 256)

        let background = CIImage(color: .black).cropped(to: paddedRect)

        // Position the tile in top-left of the padded image (can center if you prefer)
        let tileInPadded = inputCI.transformed(by: .init(translationX: 0, y: 256 - CGFloat(tileHeight)))

        let paddedImage = tileInPadded.composited(over: background)
        
        var paddedBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: 256,
            kCVPixelBufferHeightKey: 256,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        guard CVPixelBufferCreate(nil, 256, 256, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &paddedBuffer) == kCVReturnSuccess,
              let finalBuffer = paddedBuffer else { return nil }

        context.render(paddedImage, to: finalBuffer)

        return (finalBuffer, CGSize(width: tileWidth, height: tileHeight))
    }
    
    static func cropCGImageToSize(_ cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        let cropRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let debug = CIImage(cgImage: cropped)
        
        return cgImage.cropping(to: cropRect)
    }
    
    static func cropPixelBufferTrailing256(
        from pixelBuffer: CVPixelBuffer,
        targetRect: CGRect,
        context: CIContext = CIContext()
    ) -> (CVPixelBuffer, CGRect)? {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Ensure crop is 256×256, and ends at targetRect's end
        let cropOriginX = max(0, targetRect.maxX - 256)
        let cropOriginY = max(0, targetRect.maxY - 256)

        let cropRect = CGRect(x: cropOriginX, y: cropOriginY, width: 256, height: 256)

        // Flip Y for CoreImage
        let flippedCropRect = CGRect(
            x: cropRect.origin.x,
            y: CGFloat(bufferHeight) - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: flippedCropRect)
        let translated = ciImage.transformed(by: CGAffineTransform(translationX: -flippedCropRect.origin.x, y: -flippedCropRect.origin.y))

        var croppedBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: 256,
            kCVPixelBufferHeightKey: 256,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        guard CVPixelBufferCreate(nil, 256, 256, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &croppedBuffer) == kCVReturnSuccess,
              let finalBuffer = croppedBuffer else { return nil }

        context.render(translated, to: finalBuffer)

        return (finalBuffer, cropRect)
    }

    static func cropCGImageToTrailingRegion(_ cgImage: CGImage, targetRect: CGRect, within cropRect: CGRect) -> CGImage? {
        let offsetX = targetRect.origin.x - cropRect.origin.x
        let offsetY = targetRect.origin.y - cropRect.origin.y

        let flippedY = 256 - offsetY - targetRect.height
        let cropBox = CGRect(x: offsetX, y: flippedY, width: targetRect.width, height: targetRect.height)

        return cgImage.cropping(to: cropBox)
    }

}
