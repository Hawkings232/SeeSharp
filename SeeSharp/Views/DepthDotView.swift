//
//  DepthDotView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/14/25.
//
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct DepthDot
{
    let position: CGPoint
    let radius: CGFloat
    let color : Color
}

struct DepthDotsOverlay: View {
    let depthBuffer: CVPixelBuffer?
    
    private let minDepth: Float = 0.2
    private let maxDepth: Float = 5.0
    private let maxDotRadius: CGFloat = 6
    private let maxStride: Int = 8
    private let closeThreshold: Float = 1.0
    
    private let strideForMean : Int = 8
    
    @State private var dots: [DepthDot] = []
    @State private var lastBuffer: CVPixelBuffer?
    
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for dot in dots {
                    let rect = CGRect(x: dot.position.x - dot.radius / 2,
                                      y: dot.position.y - dot.radius / 2,
                                      width: dot.radius,
                                      height: dot.radius)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dot.color))
                }
            }
            .onChange(of: depthBuffer) { _, buffer in
                guard let buf = buffer else { return }
                if buf != lastBuffer {
                    lastBuffer = buf
                    computeDepthMap(from: buf, size: geo.size)
                }
            }
            .drawingGroup()
        }
    }
    
    private func computeDepthMap(from origBuffer: CVPixelBuffer, size: CGSize)
    {
        DispatchQueue.global(qos: .userInitiated).async
        {
            let buffer : CVPixelBuffer = origBuffer
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let ptr = CVPixelBufferGetBaseAddress(buffer)!
                .assumingMemoryBound(to: Float32.self)
            
            var sum: Float = 0
            var count: Int = 0
            for y in stride(from: 0, to: h, by: strideForMean) {
                for x in stride(from: 0, to: w, by: strideForMean) {
                    let d = ptr[y * w + x]
                    sum += d
                    count += 1
                }
            }
            
            let meanDepth = sum / Float(count)
            
            let (lowClip, highClip): (Float, Float) = {
                if meanDepth < closeThreshold {
                    return (
                        max(minDepth, meanDepth * 0.5),
                        min(maxDepth, meanDepth * 1.5)
                    )
                } else {
                    return (minDepth, maxDepth)
                }
            }()
            
            let window = highClip - lowClip
            var newDots: [DepthDot] = []
            
            for y in 0..<h {
                for x in 0..<w {
                    let d = ptr[y * w + x]
                    let t = (d - lowClip) / window
                    let ratio = max(0, min(1, t))
                    
                    let r = CGFloat(1 - ratio) * maxDotRadius
                    let stride = max(1, Int(1 + ratio * Float(maxStride - 1)))
                    guard x % stride == 0, y % stride == 0 else { continue }
                    
                    let px = size.width  * CGFloat(x) / CGFloat(w)
                    let py = size.height * CGFloat(y) / CGFloat(h)
                    
                    let hue   = Double((1 - ratio) * 0.33)
                    let alpha = Double(0.3 + 0.7 * (1 - ratio))
                    let dotColor = Color(hue: hue, saturation: 1, brightness: 1, opacity: alpha)
                    
                    newDots.append(DepthDot(position: CGPoint(x: px, y: py), radius: r, color: dotColor))
                }
            }
            
            DispatchQueue.main.async {
                self.dots = newDots
            }
        }
    }
}





struct DepthDotView : View
{
    @EnvironmentObject var manager : StateManager
    
    private var depthBuffer : CVPixelBuffer?
    private var confidenceBuffer : CVPixelBuffer?
    
    private let ciContext = CIContext()

    // Debugging LIDAR Depth Map:
    private func makeDepthCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        let source = CIImage(cvPixelBuffer: buffer)
        
        let clamped = source.clamped(to: source.extent)

        let minDepth: Float = 0.2
        let maxDepth: Float = 5.0
        let scale : CGFloat = CGFloat(1.0 / (maxDepth - minDepth))
        let bias : CGFloat  = CGFloat(-minDepth) * scale

        let normalized = clamped.applyingFilter("CIColorMatrix", parameters: [
            kCIInputImageKey:      clamped,
            "inputRVector":        CIVector(x: scale, y: 0,     z: 0,     w: 0),
            "inputGVector":        CIVector(x: 0,     y: scale, z: 0,     w: 0),
            "inputBVector":        CIVector(x: 0,     y: 0,     z: scale, w: 0),
            "inputBiasVector":     CIVector(x: bias,  y: bias,  z: bias,  w: 0)
        ])


        let falseColor = normalized.applyingFilter("CIFalseColor", parameters: [
            kCIInputImageKey: normalized,
            "inputColor0":    CIColor(red: 0, green: 0, blue: 0),
            "inputColor1":    CIColor(red: 1, green: 1, blue: 1)
        ])

        let output = falseColor.cropped(to: source.extent)

        return ciContext.createCGImage(output, from: output.extent)
    }
    
    var body: some View {
        ZStack
        {
            if let depth = manager.depthHandler.depthBuffer
            {
                DepthDotsOverlay(depthBuffer: depth)
            }
        }
    }
}

