import CoreML
import CoreImage
import CoreVideo
import Vision

enum  ModelHandlerError : Error, LocalizedError
{
    case predictionError
    case segmentationPredictionError
    case unexpectedBehavior
    case failedLoadingModel
    
    public var errorDescription : String?
    {
        switch self
        {
        case .predictionError:
            return NSLocalizedString("Internal Application Fault\nFailed to run model prediction on input...", comment: "Prediction Failed")
        case .failedLoadingModel:
            return NSLocalizedString(
                "Failed to load machine learning models...",
                comment: "Model Loading Failed"
            )
        case .segmentationPredictionError:
            return NSLocalizedString("Failed to run object segmentation prediction", comment: "Segmentation Prediction Failed")
        case .unexpectedBehavior:
            return NSLocalizedString(
                "An unexpected error occurred.",
                comment: "Unexpected Error"
            )
        }
    }
}

protocol ModelHandlerDelegate : AnyObject
{
    func processSegmentation(_ handler: ModelHandler, didOutput predictions: [VNRecognizedObjectObservation])
}

class ModelHandler {
    private var model: ZeroDCE_extension = try! ZeroDCE_extension()
    private var segmentationModel: YOLOv3TinyInt8LUT = try! YOLOv3TinyInt8LUT(configuration: MLModelConfiguration())
    
    private lazy var requestVisionModel : VNCoreMLRequest = {
        let visionModel = try! VNCoreMLModel(for: self.segmentationModel.model)
        return VNCoreMLRequest(model: visionModel) { request, error in
            DispatchQueue.main.async
            {
                let results : [VNRecognizedObjectObservation] = self.handleSegmentationResults(request: request, error: error)
                self.delegate?.processSegmentation(self, didOutput: results)
            }
        }
    }()
    
    private let stateManager : StateManager
    weak var delegate : ModelHandlerDelegate?
    
    init(state manager: StateManager) {
        self.stateManager = manager
        
        do
        {
            self.model = try ZeroDCE_extension();
            self.segmentationModel = try YOLOv3TinyInt8LUT(configuration: MLModelConfiguration())
        }
        catch {
            self.stateManager.error = ApplicationError(err: ModelHandlerError.failedLoadingModel)
        }
    }

    /// Takes a CVPixelBuffer, runs the ZeroDCE model’s final output (var_227)
    /// and writes it into a new 32BGRA buffer.
    func enhance(pixelBuffer: CVPixelBuffer) -> CGImage? {
        guard let output = try? model.prediction(input_image: pixelBuffer) else {
            DispatchQueue.main.async {
                self.stateManager.error = ApplicationError(err: ModelHandlerError.predictionError)
            }
            return nil
        }
        // 2) Read width/height from the original buffer (assumed 256×256).
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        // 3) Flatten the 4D var_227ShapedArray ([1×3×H×W]) into a 1D [Float]:
        //    channel‑first ordering: [ R…(w*h), G…(w*h), B…(w*h) ]
        let arr = output.var_227ShapedArray.scalars // length = 3 * w * h
        // 4) Allocate a new pixel buffer to hold BGRA data
        var outPB: CVPixelBuffer?
        CVPixelBufferCreate(
          nil,
          w, h,
          kCVPixelFormatType_32BGRA,
          nil,
          &outPB
        )
        guard let dest = outPB else { return nil }

        // 5) Lock the base address so we can write raw bytes
        CVPixelBufferLockBaseAddress(dest, [])
        let ptr = CVPixelBufferGetBaseAddress(dest)!
                     .assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(dest)
        let channelSize = w * h  // number of pixels in one color channel

        // 6) Loop over every pixel position
        for y in 0..<h {
          for x in 0..<w {
            let idx = y * w + x

            // 6a) Read each channel’s Float [0…1]
            let Rf = arr[idx]           // Red channel
            let Gf = arr[channelSize + idx]     // Green channel
            let Bf = arr[2*channelSize + idx]   // Blue channel

            // 6b) Convert floats to 0–255 UInt8
            let R8 = UInt8(clamping: Int(Rf * 255))
            let G8 = UInt8(clamping: Int(Gf * 255))
            let B8 = UInt8(clamping: Int(Bf * 255))

            // 6c) Compute byte offset for BGRA layout
            let off = y * bpr + x * 4

            // 6d) Write in BGRA order
            ptr[off + 0] = B8   // Blue
            ptr[off + 1] = G8   // Green
            ptr[off + 2] = R8   // Red
            ptr[off + 3] = 255  // Alpha
          }
        }

        // 7) Unlock and return the enhanced buffer
        CVPixelBufferUnlockBaseAddress(dest, [])
        
        if self.stateManager.useObjectSegmentation
        {
            self.queryObjectSegmentation(from: dest)
        }
        
        let ciImage = CIImage(cvPixelBuffer: dest)
        return self.stateManager.ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    func enhanceThroughTiling(pixelBuffer: CVPixelBuffer) -> CGImage? {
        let tileSize = 256
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var outputImage = CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        for y in stride(from: 0, to: height, by: tileSize) {
            for x in stride(from: 0, to: width, by: tileSize) {
                let rect = CGRect(x: x, y: y, width: min(tileSize, width - x), height: min(tileSize, height - y))
                guard
                      let (expandedBuffer, originalSize) = Utilities.cropPixelBufferTrailing256(from: pixelBuffer, targetRect: rect),
                      let tileCG = self.enhance(pixelBuffer: expandedBuffer),
//                      let tileCG = self.stateManager.ciContext.createCGImage(CIImage(cvPixelBuffer: expandedBuffer).settingAlphaOne(in: CGRect(x: 0, y: 0, width: 256, height: 256)), from: CGRect(x: 0, y: 0, width: 256, height: 256), format: .RGBA8, colorSpace: colorSpace),
                      let finalTile = Utilities.cropCGImageToTrailingRegion(tileCG, targetRect: rect, within: originalSize)
                else {
                    continue
                }

                print("Tile (\(x), \(y)) — size: \(rect.width)x\(rect.height)")
                
                let mirroredY = CGFloat(height - y - Int(rect.height))
                let tileCI = CIImage(cgImage: finalTile)
                    .transformed(by: CGAffineTransform(translationX: CGFloat(x), y: CGFloat(mirroredY)))
                
                outputImage = tileCI.composited(over: outputImage)
            }
        }

        return stateManager.ciContext.createCGImage(outputImage, from: outputImage.extent)
    }
    
    func queryObjectSegmentation(from buffer : CVPixelBuffer)
    {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do
        {
            try handler.perform([requestVisionModel])
        }
        catch
        {
            self.stateManager.error = ApplicationError(err: ModelHandlerError.segmentationPredictionError)
        }
    }
    
    func handleSegmentationResults(request : VNRequest, error : Error?) -> [VNRecognizedObjectObservation]
    {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
        return results
    }
}
