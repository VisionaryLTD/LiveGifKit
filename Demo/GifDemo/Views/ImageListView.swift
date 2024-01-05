//
//  RecommendView.swift
//  GifDemo
//
//  Created by tangxiaojun on 2024/1/5.
//

import SwiftUI

struct ImageListView: View {
    var uiImages: [UIImage] = []
    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 180)),
                GridItem(.adaptive(minimum: 120, maximum: 180)),
                GridItem(.adaptive(minimum: 120, maximum: 180)),
            ]) {
                ForEach(uiImages, id: \.self) { image in
                   Image(uiImage: image)
                       .resizable()
                       .aspectRatio(contentMode: .fit)
               }
            }
        }
    }
}

 
