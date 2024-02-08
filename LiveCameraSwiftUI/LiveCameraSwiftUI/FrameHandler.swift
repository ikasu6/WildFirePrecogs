//
//  FrameHandler.swift
//  LiveCameraSwiftUI
//
//  Created by Ishwarya Kasu on 2/7/24.
//

import AVFoundation
import CoreImage

class FrameHandler : NSObject, ObservableObject {
    @Published var frame : CGImage?
    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()
    //to check initially if the user has enbled camera access or not
    override init(){
        super.init()
        checkPermission()
        sessionQueue.async { [unowned self] in
            self.setupCaptureSession ()
            self.captureSession.startRunning ()
        }
        
    }
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: // The user has previously granted access to the camera.
            permissionGranted = true
        case .notDetermined: // The user has not yet been asked for camera access.
            requestPermission()
            //Combine the two other cases into the default case
        default:
            permissionGranted = false
        }
    }
    func requestPermission(){
        AVCaptureDevice.requestAccess(for: .video) {[unowned self] granted in self.permissionGranted = granted
        }
    }
    func setupCaptureSession() {
        let videOutput = AVCaptureVideoDataOutput ()
        guard permissionGranted else { return }
        guard let videoDevice = AVCaptureDevice.default (.builtInDualCamera,for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput (device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
            
        videOutput.setSampleBufferDelegate (self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput (videOutput)
        videOutput.connection(with: .video)?.videoRotationAngle = 90
    }
}

extension FrameHandler: AVCaptureVideoDataOutputSampleBufferDelegate{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cgImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else {return}
        
        DispatchQueue.main.async {
            self.frame = cgImage
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CGImage?{
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)else{ return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent)else { return nil }
        
        return cgImage
    }
}
