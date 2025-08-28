//
//  DepthMapHandler.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/14/25.
//
import SwiftUI
import ARKit

class DepthMapHandler : NSObject, ObservableObject, ARSessionDelegate
{
    @Published var depthBuffer : CVPixelBuffer?
    
    private let session = ARSession()
    private var trackingState : ARCamera.TrackingState?
    
    private var previousDepth : [Float32]? = nil
    private let alpha : Float = 0.5
    
    private var stateManager : StateManager
    @Published var error : ApplicationError?
    
    init(state manager: StateManager) {
        self.stateManager = manager
        
        super.init()
        session.delegate = self
        
        if self.stateManager.useLidar
        {
            self.startSession()
            self.stateManager.torchMode = self.checkTorchStatus() == .notSupported ? .notSupported : .off
        }
    }
    
    deinit {
        session.pause()
        session.delegate = nil
    }
    
    func filterOutPixels(depth : CVPixelBuffer, confidence: CVPixelBuffer)
    {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }

        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        let count = width * height

        let depthPointer = CVPixelBufferGetBaseAddress(depth)!.assumingMemoryBound(to: Float32.self)
        let confidencePointer = CVPixelBufferGetBaseAddress(confidence)!.assumingMemoryBound(to: UInt8.self)
        
        if previousDepth == nil
        {
            previousDepth = [Float32](repeating: 0, count: count)
            for i in 0..<count {
                previousDepth![i] = depthPointer[i]
            }
            return
        }
        for i in 0..<count {
            let conf = confidencePointer[i]

            let currentDepth = depthPointer[i]
            var smoothed: Float32

            if conf <= 1 {
                smoothed = alpha * previousDepth![i] + (1 - alpha) * currentDepth
            } else {
                smoothed = (1 - alpha) * previousDepth![i] + alpha * currentDepth
            }

            previousDepth![i] = smoothed
        }
    }
    
    func session (_ session: ARSession, didUpdate frame: ARFrame)
    {
        if self.trackingState == .notAvailable { return }
        if let depth = frame.sceneDepth?.depthMap, let confidenceMap = frame.sceneDepth?.confidenceMap
        {
            filterOutPixels(depth: depth, confidence: confidenceMap)
            DispatchQueue.main.async
            {
                guard let rotated = Utilities.rotate90(buffer: depth) else { return }
                self.depthBuffer = rotated
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        self.error = ApplicationError(err: error)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera : ARCamera)
    {
        if (self.trackingState != camera.trackingState)
        {
            self.stateManager.pushNotification(content: "AR Tracking State Changed to \(camera.trackingState)")
        }
        self.trackingState = camera.trackingState
    }
    
    func stopSession()
    {
        session.pause()
    }
    
    func startSession()
    {
        self.stateManager.pushNotification(content: "Using LiDAR For Low-Light Scanning")
        
        let config = ARWorldTrackingConfiguration()
        // config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .none

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func checkTorchStatus() -> TorchMode
    {
        guard let device = AVCaptureDevice.default(
                .builtInLiDARDepthCamera,
                for: .video,
                position: .back)
        else
        {
            return .notSupported
        }
        
        if device.hasTorch
        {
            return device.torchMode == .on ? TorchMode.on : TorchMode.off
        }
        else
        {
            return .notSupported
        }
    }
    
    func toggleTorch(on: TorchMode) -> TorchMode {
        guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back) else { return .notSupported }
                
        guard device.hasTorch else { return .notSupported }
        do {
            try device.lockForConfiguration()
            if on == TorchMode.on && device.isTorchModeSupported(.on)
            {
                try device.setTorchModeOn(level: 0.002)
                device.unlockForConfiguration()
                return .on
            }
            else
            {
                device.torchMode = .off
                device.unlockForConfiguration()
                return .off
            }
        }
        catch
        {
            self.stateManager.pushNotification(
                content: "Error configuring torch: \(error.localizedDescription)",
                duration: 2
            )
        }
        return .notSupported
    }
}
