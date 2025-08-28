//
//  CameraFrameView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/17/25.
//

import SwiftUI
import Vision
import ActivityIndicatorView

struct DetectionOverlay: View {
    @State var showDetectionIcon = true
    
    let detections: [VNRecognizedObjectObservation]
    let imageSize: CGSize
    let viewSize: CGSize

    var body: some View {
        ForEach(detections.indices, id: \.self) { i in
            let bbox = detections[i].boundingBox
            let label = detections[i].labels.first?.identifier ?? "Unknown"

            let centerX = bbox.midX * viewSize.width
            let centerY = (1 - bbox.midY) * viewSize.height

            VStack(spacing: 4)
            {
                Text(label.capitalized)
                    .font(.caption)
                    .bold()
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                
            }
            .position(x: centerX, y: centerY)
        }
    }
}

struct CameraFrameView : View
{
    @EnvironmentObject var manager : StateManager

    var body : some View
    {
        ZStack(alignment: .bottom)
        {
            HStack
            {
                VStack(alignment: .leading)
                {
                    Text("Diagnostics Enabled")
                    Text("Frames / Sec: X/s")
                    Text("Flashlight: Off")
                    Text("Lidar Activation: Off")
                }
                .foregroundColor(.white)
                .font(.system(.body, design: .monospaced))
                .padding()
                .zIndex(1)
                
                Spacer()
            }
            if let frame = manager.frameHandler.frame
            {
                GeometryReader { geo in
                    let imageSize = CGSize(width: frame.width, height: frame.height)
                    let displaySize = geo.size
                    
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .overlay(
                            DetectionOverlay(
                                detections: manager.frameHandler.detections ?? [],
                                imageSize: imageSize,
                                viewSize: displaySize
                            )
                        )
                }
            }
            else
            {
                ZStack
                {
                    Color.black
                        .opacity(0.7)
                    
                    HStack
                    {
                        Image(systemName: "photo.on.rectangle.angled.fill")
                            .foregroundColor(.white)
                        Text("No Image Detected...")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }.zIndex(1)
            }
        }
    }
}

#Preview
{
    ContentView()
}
