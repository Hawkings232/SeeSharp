//
//  ModelTestView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 6/5/25.
//
import SwiftUI
import UIKit
import CoreVideo

extension UIImage {
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width, height,
                                         kCVPixelFormatType_32ARGB,
                                         attrs, &pixelBuffer)

        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pb, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pb, [])

        return pb
    }
}


struct ModelTestView : View
{
    @State private var enhancedImage: UIImage?

        private let model = try! ZeroDCE_extension()

        var body: some View {
            VStack {
                if let image = enhancedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    Text("Enhancing...")
                }
            }
            .onAppear(perform: runModel)
        }

        func runModel() {
            guard let inputImage = UIImage(named: "dark_room"),
                  let inputBuffer = inputImage.pixelBuffer(width: 256, height: 256),
                  let output = try? model.prediction(input_image: inputBuffer) else {
                print("Failed to load image or predict")
                return
            }

            let scalars = output.var_227ShapedArray.scalars
            let width = 256
            let height = 256
            let channelSize = width * height

            // Create raw RGBA pixel data
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * width + x
                    let r = scalars[idx]
                    let g = scalars[channelSize + idx]
                    let b = scalars[2 * channelSize + idx]
                    let offset = (y * width + x) * 4
                    pixels[offset]     = UInt8(clamping: Int(b * 255)) // B
                    pixels[offset + 1] = UInt8(clamping: Int(g * 255)) // G
                    pixels[offset + 2] = UInt8(clamping: Int(r * 255)) // R
                    pixels[offset + 3] = 255                            // A
                }
            }

            // Convert pixel data to UIImage
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let ctx = CGContext(data: &pixels,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: width * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
               let cgImage = ctx.makeImage() {
                let uiImage = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.enhancedImage = uiImage
                }
            }
        }
}
