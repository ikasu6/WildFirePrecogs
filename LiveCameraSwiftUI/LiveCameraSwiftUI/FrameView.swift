//
//  FrameView.swift
//  LiveCameraSwiftUI
//
//  Created by Ishwarya Kasu on 2/6/24.
//

import SwiftUI

struct FrameView: View {
    
    var image : CGImage?
    private let label = Text("frame")
    
    var body: some View {
        if let image = image{
            Image(image, scale: 1.0, orientation: .up, label: label)
        }else{
            Color.black
        }
    }
}

#Preview {
    FrameView()
}
