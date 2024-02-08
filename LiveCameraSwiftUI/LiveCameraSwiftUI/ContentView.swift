//
//  ContentView.swift
//  LiveCameraSwiftUI
//
//  Created by Ishwarya Kasu on 2/6/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = FrameHandler()
    var body: some View {
        FrameView (image: model.frame)
            .ignoresSafeArea()
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
        
    }
    
}

