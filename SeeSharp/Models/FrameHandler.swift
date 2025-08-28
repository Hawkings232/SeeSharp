//
//  FrameHandler.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/11/25.
//
import AVFoundation
import CoreImage
import CoreML
import Vision

enum FrameHandlerError : Error, LocalizedError
{
    case deviceConfigurationFailed
    case unexpectedBehavior
    
    public var errorDescription : String?
    {
        switch self
        {
        case .deviceConfigurationFailed:
            return NSLocalizedString("Device configuration failed.", comment: "Configuration Failed")
        case .unexpectedBehavior:
            return NSLocalizedString(
                "An unexpected error occurred.",
                comment: "Unexpected Error"
            )
        }
    }
}

class FrameHandler : NSObject, ObservableObject
{
    @Published var frame: CGImage?
    @Published var error : ApplicationError?
    @Published var detections : [VNRecognizedObjectObservation]?
    @Published var fps : Double = 0
    
    private var permissionChecked = false
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var device : AVCaptureDevice?
    private var photoDelegate : PhotoCaptureDelegate?
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var times = [Double]()
    
    private let context = CIContext()
    private var currentPosition : AVCaptureDevice.Position = .back
    
    lazy private var modelHandler : ModelHandler = {
        let modelHandler = ModelHandler(state: self.stateManager)
        modelHandler.delegate = self
        return modelHandler
    }()
    
    private var stateManager : StateManager
    
    init(state manager: StateManager)
    {
        self.stateManager = manager
        
        super.init()
        self.checkPermission()
        sessionQueue.async { [unowned self] in
            self.setupCaptureSession(position: self.currentPosition)
        }
    }
    
    func checkPermission()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
        case .authorized:
            self.permissionChecked = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
                self.permissionChecked = granted
            }
        default:
            break
        }
    }
    
    
    func setupCaptureSession(position: AVCaptureDevice.Position)
    {
        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        let videoOutput = AVCaptureVideoDataOutput()

        guard permissionChecked else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }

        self.device = device
        self.currentPosition = position

        guard let deviceInput = try? AVCaptureDeviceInput(device: device) else { return }
        guard captureSession.canAddInput(deviceInput) else { return }
        captureSession.addInput(deviceInput)

        if captureSession.canAddOutput(self.photoOutput) {
            captureSession.addOutput(self.photoOutput)
        } else {
            self.stateManager.error = ApplicationError(err: FrameHandlerError.unexpectedBehavior)
        }

        do {
            try device.lockForConfiguration()
            device.unlockForConfiguration()
        } catch {
            self.stateManager.error = ApplicationError(err: FrameHandlerError.deviceConfigurationFailed)
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = position == .front
        }

        captureSession.commitConfiguration()
        
        if !self.stateManager.useLidar
        {
            self.startSession()
            DispatchQueue.main.sync
            {
                self.stateManager.torchMode = self.checkTorchStatus() == .notSupported ? .notSupported : .off
            }
        }
    }

    
    func takePhoto(completion: @escaping (CGImage?) -> Void)
    {
        let settings = AVCapturePhotoSettings()
        if let supported = device?.activeFormat.supportedMaxPhotoDimensions
        {
            settings.maxPhotoDimensions = supported.first!
        }
       
        let rotationAngle = photoOutput.connection(with: .video)?.videoRotationAngle ?? 0
        
        let delegate = PhotoCaptureDelegate(context: self.stateManager.ciContext, rotationAngle: rotationAngle, modelHandler: self.modelHandler, completion: { image in
            DispatchQueue.main.async {
                completion(image)
                self.photoDelegate = nil
            }
        })
        
        self.photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
    
    func flipCamera()
    {
        sessionQueue.async { [unowned self] in
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            self.setupCaptureSession(position: newPosition)
        }
    }

 
    func startSession() {
        self.stateManager.pushNotification(content: "Using Camera For Low-Light Scanning")
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func checkTorchStatus() -> TorchMode
    {
        guard let input = captureSession.inputs.first as? AVCaptureDeviceInput else { return .notSupported }
        let device = input.device
        
        if device.hasTorch
        {
            return device.torchMode == .on ? TorchMode.on : TorchMode.off
        }
        else
        {
            return .notSupported
        }
    }
    
    func toggleTorch(on: TorchMode) -> TorchMode
    {
        guard let input = captureSession.inputs.first as? AVCaptureDeviceInput else { return .notSupported}
        let device = input.device
        
        if !device.hasTorch
        {
            return .notSupported
        }
        
        do
        {
            try device.lockForConfiguration()
            if on == .on && device.isTorchModeSupported(.on)
            {
                try device.setTorchModeOn(level: 0.05)
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
            self.stateManager.pushNotification(content: "Error configuring torch activation!", duration: 2)
        }
        
        return .notSupported
    }
}

extension FrameHandler : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        guard let cgImage = imageFromSampleBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async
        { [unowned self] in
            self.frame = cgImage
        }
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CGImage? {
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let t = CMTimeGetSeconds(ts)

        times.append(t)
        let cutoff = t - 1.5
        while times.count > 1, times.first! < cutoff { times.removeFirst() }

        if times.count >= 2 {
            let duration = max(times.last! - times.first!, .ulpOfOne)
            let fpsNow = Double(times.count - 1) / duration
            DispatchQueue.main.async { self.fps = fpsNow }
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        guard let resized = Utilities.resize(buffer: imageBuffer) else { return nil }
        guard let enhanced = self.modelHandler.enhance(pixelBuffer: resized) else { return nil }

//        let ciImage = CIImage(cvPixelBuffer: resized)
//        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
//        
        return enhanced
    }
}

extension FrameHandler : ModelHandlerDelegate
{
    func processSegmentation(_ handler: ModelHandler, didOutput predictions: [VNRecognizedObjectObservation]) {
        self.detections = predictions
    }
}

class PhotoCaptureDelegate : NSObject, AVCapturePhotoCaptureDelegate {
    
    private let completion : (CGImage?) -> Void // Callback
    private let context : CIContext
    private let rotationAngle : CGFloat
    private let modelHandler : ModelHandler
    
    init(context : CIContext, rotationAngle : CGFloat, modelHandler: ModelHandler, completion: @escaping (CGImage?) -> Void)
    {
        self.rotationAngle = rotationAngle
        self.context = context
        self.completion = completion
        self.modelHandler = modelHandler
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?)
    {
        guard let cgImageRepresentation = photo.cgImageRepresentation() else
        {
            completion(nil)
            return
        }
        
        guard let pixelBufferRepresentation = Utilities.cgImageToPixelBuffer(from: cgImageRepresentation) else
        {
            completion(nil)
            return
        }
        
        let product = self.modelHandler.enhanceThroughTiling(pixelBuffer: pixelBufferRepresentation)
        completion(product)
    }
}

//
//extension FrameHandler: AVCaptureDepthDataOutputDelegate {
//    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
//                         didOutput depthData: AVDepthData,
//                         timestamp: CMTime,
//                         connection: AVCaptureConnection) {
//
//        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
//        guard let depthMap = DepthMapHandler.rotate90(buffer: convertedDepth.depthDataMap) else {return }
//        
//        let ciImage = CIImage(cvPixelBuffer: depthMap)
//        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
//        DispatchQueue.main.async { [unowned self] in
//            self.depthMapImage = cgImage
//        }
//    }
//}
//
