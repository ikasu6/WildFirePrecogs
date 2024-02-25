

import UIKit
import AVFoundation
import Vision

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

    
    @objc func doScan(sender: UIButton!){
        self.isTapped = true
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
    
    private func setCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .back).devices.first else {
                fatalError("No back camera device found.")
        }
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    private func showCameraFeed() {
        self.previewLayer.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.frame
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
    
    private func detectRectangle(in image: CVPixelBuffer) {

        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                
                guard let results = request.results as? [VNRectangleObservation] else { return }
                print("______________")
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
    
    
    
    func drawBoundingBox(rect : VNRectangleObservation) {
    
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.frame.height)
        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.frame.width, y: self.previewLayer.frame.height)

        let bounds = rect.boundingBox.applying(scale).applying(transform)
        createLayer(in: bounds)

    }

    private func createLayer(in rect: CGRect) {

        maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.cornerRadius = 10
        maskLayer.opacity = 0.75
        maskLayer.borderColor = UIColor.red.cgColor
        maskLayer.borderWidth = 5.0
        
        previewLayer.insertSublayer(maskLayer, at: 1)

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
