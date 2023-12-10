//
//  PhotoPickerView.swift
//  GifDemo
//
//  Created by 汤小军 on 2023/12/10.
//

import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @Binding var pickedItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker("", selection: $pickedItem, matching: .livePhotos)
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .ignoresSafeArea(edges: .top)
    }
}

 
