

import UIKit
import AVFoundation
import Vision
import Darwin

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isTapped = false
    private var maskLayer = CAShapeLayer()
    private var isProcessingDetections: Bool = true

    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setCameraInput()
        self.showCameraFeed()
        self.setCameraOutput()
        //setupCaptureButton()
       
        
    }
    
    
    private func setCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [ .builtInTripleCamera],
            mediaType: .video,
            position: .back).devices.first else {
                fatalError("No back camera device found.")
        }
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    private func setCameraOutput() {
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.addOutput(self.videoDataOutput)
        
        guard let connection = self.videoDataOutput.connection(with: AVMediaType.video),
            connection.isVideoOrientationSupported else { return }
        
        connection.videoOrientation = .portrait
        
        
        
    }
    
    private func showCameraFeed() {
        self.previewLayer.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.frame
    }
    
    
    override func viewDidAppear(_ animated: Bool) {

        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.startRunning()
    }

    
    override func viewDidDisappear(_ animated: Bool) {
        
        self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        self.captureSession.stopRunning()
    }
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
    }
    


    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection) {
        
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("unable to get image from sample buffer")
            return
        }
        
        self.detectRectangle(in: frame)
        
    }
    

    
//    private func detectRectangle2(in image: CVPixelBuffer) {
//
//        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest, error: Error?) in
//            DispatchQueue.main.async {
//
//                guard let results = request.results as? [VNRectangleObservation] else { return }
//                print("_______________")
//                print(results)
//                self.removeMask()
//
//                guard let rect = results.first else{return}
//                    self.drawBoundingBox(rect: rect)
//                    if self.isTapped{
//                        self.isTapped = false
//                        self.doPerspectiveCorrection(rect, from: image)
//
//                    }
//            }
//        })
//
//        //Setting the Parameters of VNrectangle detection request
//        request.minimumAspectRatio = VNAspectRatio(1.3)
//        request.maximumAspectRatio = VNAspectRatio(1.6)
//        request.minimumSize = Float(0.5)
//        request.maximumObservations = 1
//
//
//        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
//        try? imageRequestHandler.perform([request])
//
//    }
    
    
    
    
    
    private func detectRectangle(in image: CVPixelBuffer) {
        guard isProcessingDetections else {
            return
        }
        // Configuring  the rectangle detection request
        let rectangleDetectionRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.processDetectionResults(request.results, in: image)
            }
        }
        configureDetectionRequest(rectangleDetectionRequest)
        performDetection(with: rectangleDetectionRequest, on: image)
    }

    private func configureDetectionRequest(_ request: VNDetectRectanglesRequest) {
        request.minimumAspectRatio = VNAspectRatio(1.3)
        request.maximumAspectRatio = VNAspectRatio(1.6)
        request.minimumSize = Float(0.5)
        request.maximumObservations = 1
    }

    private func performDetection(with request: VNRequest, on image: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try? handler.perform([request])
    }


    
    private var lastDetectedRectangle: VNRectangleObservation?
    private var noChangeCounter: Int = 0 // Counter for consecutive readings without significant change
    private let noChangeThreshold: Int = 15 // Threshold for changing the bounding box color
    private var shouldDrawGreenBoundingBox: Bool = false // Flag to indicate bounding box color
    private var autoCaptureEnabled: Bool = true


    private func processDetectionResults(_ results: [Any]?, in image: CVPixelBuffer ) {
        // any rectangle observations
        guard let observations = results as? [VNRectangleObservation], !observations.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.removeMask() // Clear existing bounding box if no rectangles are detected
                self?.lastDetectedRectangle = nil // Reset the last detected rectangle
            }
            return
        }
        
        // logic to proceed if there's at least one detected rectangle
        if let firstRectangle = observations.first {
                if hasRectangleChanged(rectangle: firstRectangle) {
                    noChangeCounter = 0 // Reset counter on change
                    shouldDrawGreenBoundingBox = false // Reset color indicator
                } else {
                    noChangeCounter += 1 // Increment counter if no change
                    if noChangeCounter >= noChangeThreshold {
                        shouldDrawGreenBoundingBox = true // Indicate to draw bounding box in green
                        performAutomaticCapture(with: firstRectangle, from: image) // Trigger automatic capture
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.removeMask() // Clear any existing bounding box before drawing a new one
                    self.drawBoundingBox(rect: firstRectangle)
                    self.lastDetectedRectangle = firstRectangle // Update the last detected rectangle
                }
        }
    }
    
    private func performAutomaticCapture(with rectangleObservation: VNRectangleObservation, from buffer: CVImageBuffer) {
        guard shouldDrawGreenBoundingBox, autoCaptureEnabled else {
            return
        }

        autoCaptureEnabled = false // to prevent further captures until  reset

        // to do perspective correction and save the image
        DispatchQueue.main.async {
            self.doPerspectiveCorrection(rectangleObservation, from: buffer)
            //  popup notification
            self.showAlertWith(title: "Image Captured", message: "The image has been automatically captured and saved click OK to proceed.")
            
            // Resetting autoCaptureEnabled flag after a delay to allow for new captures
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { // 5 seconds delay
                self.autoCaptureEnabled = true
                self.resetDetectionState()
            }
        }
    }
    
    
    private func resetDetectionState() {
        self.lastDetectedRectangle = nil
        self.noChangeCounter = 0
        self.shouldDrawGreenBoundingBox = false
        self.autoCaptureEnabled = true // Ensure this is ready for the next detection cycle
    }
    
    private func hasRectangleChanged(rectangle: VNRectangleObservation) -> Bool {
        guard let lastRectangle = lastDetectedRectangle else {
            return true // No last rectangle, so consider this as changed
        }
        // Implementing comparison logic here.
        let lastCenter = lastRectangle.boundingBox.origin
        let currentCenter = rectangle.boundingBox.origin
        let distanceThreshold: CGFloat = 0.1 // Adjust based on your needs
        let distance = hypot(lastCenter.x - currentCenter.x, lastCenter.y - currentCenter.y)
        return distance > distanceThreshold
    }


    private func shouldUpdateBoundingBox(for newRectangle: VNRectangleObservation) -> Bool {
        guard let lastRectangle = lastDetectedRectangle else {
            return true
        }
        

        return !areRectanglesSimilar(rect1: lastRectangle, rect2: newRectangle)
    }

    private func areRectanglesSimilar(rect1: VNRectangleObservation, rect2: VNRectangleObservation) -> Bool {

        let tolerance: CGFloat = 0.2 // Adjust based on your needs
        let a = abs(rect1.bottomLeft.x - rect2.bottomLeft.x)
        let b = abs(rect1.topRight.x - rect2.topRight.x)
        let delta = a + b
        return delta < tolerance
    }

    



    
    

    
//    func drawBoundingBox(rect : VNRectangleObservation) {
//
//        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.frame.height)
//        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.frame.width, y: self.previewLayer.frame.height)
//
//        let bounds = rect.boundingBox.applying(scale).applying(transform)
//        createLayer(in: bounds)
//
//
//    }
    
    
    func drawBoundingBox(rect: VNRectangleObservation) {
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.frame.height)
        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.frame.width, y: self.previewLayer.frame.height)

        let bounds = rect.boundingBox.applying(scale).applying(transform)
        createLayer(in: bounds, shouldDrawGreen: shouldDrawGreenBoundingBox)
    }
    
    
    private func createLayer(in rect: CGRect, shouldDrawGreen: Bool) {
        maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.cornerRadius = 10
        maskLayer.opacity = 0.75
        maskLayer.borderColor = shouldDrawGreen ? UIColor.green.cgColor : UIColor.red.cgColor
        maskLayer.borderWidth = 5.0
        
        previewLayer.insertSublayer(maskLayer, at: 1)
    }


//    private func createLayer(in rect: CGRect) {
//
//        maskLayer = CAShapeLayer()
//        maskLayer.frame = rect
//        maskLayer.cornerRadius = 10
//        maskLayer.opacity = 0.75
//        maskLayer.borderColor = UIColor.red.cgColor
//        maskLayer.borderWidth = 5.0
//
//        previewLayer.insertSublayer(maskLayer, at: 1)
//
//    }
    
    
    @objc func doScan(sender: UIButton!){
        self.isTapped = true
    }
    
    
    func doPerspectiveCorrection(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) {
        var ciImage = CIImage(cvImageBuffer: buffer)

        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)

        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let output = UIImage(cgImage: cgImage)

        // Save the image to the Photos album
        UIImageWriteToSavedPhotosAlbum(output, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // We got back an error!
            showAlertWith(title: "Save error", message: error.localizedDescription)
        } else {
            showAlertWith(title: "Saved :)", message: "Your image has been saved to your photos.")
        }
    }
    
//    func showAlertWith(title: String, message: String) {
//        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
//        ac.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
//            self.resetDetectionState() // Reset when the user acknowledges
//        }))
//        present(ac, animated: true)
//    }
    
    func showAlertWith(title: String, message: String) {
        // Pause detections
        isProcessingDetections = false

        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            // Resume detections
            self.isProcessingDetections = true
            self.resetDetectionState() // Reset detection state if needed
        }))
        present(ac, animated: true)
    }
    
    func removeMask() {
            maskLayer.removeFromSuperlayer()

    }
}

extension CGPoint {
   func scaled(to size: CGSize) -> CGPoint {
       return CGPoint(x: self.x * size.width,
                      y: self.y * size.height)
   }
}
