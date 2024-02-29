

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
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setCameraInput()
        self.showCameraFeed()
        self.setCameraOutput()
        setupCaptureButton()
       
        
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
    
    func setupCaptureButton() {
        let captureButton = UIButton(type: .system) // Creates a new UIButton with the system type, which gives it a default style.
        captureButton.setTitle("Capture", for: .normal) // Sets the button title.
        captureButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20) // Optional: Sets the font of the button title.
        captureButton.backgroundColor = UIColor.systemBlue // Sets the background color of the button.
        captureButton.setTitleColor(UIColor.white, for: .normal) // Sets the title color.
        captureButton.layer.cornerRadius = 25 // Optional: Sets the corner radius to make the button rounded.
        
        captureButton.addTarget(self, action: #selector(doScan(sender:)), for: .touchUpInside) // Adds an action to the button.
        
        self.view.addSubview(captureButton) // Adds the button to the view hierarchy.
        
        captureButton.translatesAutoresizingMaskIntoConstraints = false // Disables autoresizing mask translation into Auto Layout constraints.
        
        // Constraints for the button
        NSLayoutConstraint.activate([
            captureButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20), // Positions the button 20 points from the bottom safe area.
            captureButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // Centers the button horizontally.
            captureButton.widthAnchor.constraint(equalToConstant: 200), // Sets the button width.
            captureButton.heightAnchor.constraint(equalToConstant: 50) // Sets the button height.
        ])
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
    

    
    private func detectRectangle2(in image: CVPixelBuffer) {

        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                
                guard let results = request.results as? [VNRectangleObservation] else { return }
                print("_______________")
                print(results)
                self.removeMask()
                
                guard let rect = results.first else{return}
                    self.drawBoundingBox(rect: rect)
                    if self.isTapped{
                        self.isTapped = false
                        self.doPerspectiveCorrection(rect, from: image)
                        
                    }
            }
        })
        
        
        
        
    
        request.minimumAspectRatio = VNAspectRatio(1.3)
        request.maximumAspectRatio = VNAspectRatio(1.6)
        request.minimumSize = Float(0.5)
        request.maximumObservations = 1
        
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try? imageRequestHandler.perform([request])
        
    }
    
    
    
    private func detectRectangle(in image: CVPixelBuffer) {
        // Configure the rectangle detection request
        let rectangleDetectionRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.processDetectionResults(request.results, in: image)
                
                
            }
        }
        configureDetectionRequest(rectangleDetectionRequest)
        
        // Perform the request on the given image
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


    private func processDetectionResults(_ results: [Any]?, in image: CVPixelBuffer) {
        // Check if there are any rectangle observations
        guard let observations = results as? [VNRectangleObservation], !observations.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.removeMask() // Clear existing bounding box if no rectangles are detected
                self?.lastDetectedRectangle = nil // Reset the last detected rectangle
            }
            return
        }
        
        // Proceed if there's at least one detected rectangle
        if let firstRectangle = observations.first {
                if hasRectangleChanged(rectangle: firstRectangle) {
                    noChangeCounter = 0 // Reset counter on change
                    shouldDrawGreenBoundingBox = false // Reset color indicator
                } else {
                    noChangeCounter += 1 // Increment counter if no change
                    if noChangeCounter >= noChangeThreshold {
                        shouldDrawGreenBoundingBox = true // Indicate to draw bounding box in green
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
    
    
    
    private func hasRectangleChanged(rectangle: VNRectangleObservation) -> Bool {
        guard let lastRectangle = lastDetectedRectangle else {
            return true // No last rectangle, so consider this as changed
        }
        // Implement your comparison logic here. This is a simple example that checks if the centers are significantly different.
        let lastCenter = lastRectangle.boundingBox.origin
        let currentCenter = rectangle.boundingBox.origin
        let distanceThreshold: CGFloat = 0.1 // Adjust based on your needs
        let distance = hypot(lastCenter.x - currentCenter.x, lastCenter.y - currentCenter.y)
        return distance > distanceThreshold
    }


    private func shouldUpdateBoundingBox(for newRectangle: VNRectangleObservation) -> Bool {
        guard let lastRectangle = lastDetectedRectangle else {
            return true // Always update if there's no previous rectangle
        }
        
        // Implement comparison logic here. This is a placeholder for a simple comparison.
        // You might want to compare the center points, the area, or the corners of the rectangles.
        return !areRectanglesSimilar(rect1: lastRectangle, rect2: newRectangle)
    }

    private func areRectanglesSimilar(rect1: VNRectangleObservation, rect2: VNRectangleObservation) -> Bool {
        // This function should return true if the rectangles are considered similar.
        // For simplicity, let's just check if the center points are approximately equal.
        // You can adjust the tolerance and comparison criteria based on your requirements.
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
    
    func showAlertWith(title: String, message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
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
