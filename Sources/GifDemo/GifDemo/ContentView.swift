//
//  ContentView.swift
//  GifDemo
//
//  Created by 汤小军 on 2023/12/10.
//

import SwiftUI
import PhotosUI
import LiveGifKit
import Kingfisher

struct ContentView: View {
    @State var photoItem: PhotosPickerItem?
    @State var showPicker: Bool = false
    @State var images = [UIImage]()
    @State var noBgimages = [UIImage]()
    @State var gifImages = [UIImage]()
    @State var gifUrl: URL?
    
    @State var fps: Double = 15
    @State var giffps: Double = 15
    @State var totalTime = 0.0
    var body: some View {
        VStack {
      
            Slider(value: $fps, in: 5...60, step: 5)
            .overlay(Text("每秒帧数(FPS): \(Int(fps))")
                         .foregroundColor(.primary)
                         .font(.headline)
                         .offset(x: 0, y: -20))
            
            Slider(value: $giffps, in: 5...60, step: 5)
            .overlay(Text("GIF每秒帧数(FPS): \(Int(giffps))")
                         .foregroundColor(.primary)
                         .font(.headline)
                         .offset(x: 0, y: -20))
            
            Spacer()
            if gifUrl?.absoluteString.count ?? 0 > 0 {
               
                KFAnimatedImage(gifUrl)
                              
                               .scaledToFit()
                               .frame(maxHeight: .infinity)
                
                Text("总帧数: \(self.gifImages.count)")
                Text("总耗时: \(self.totalTime)")
                
            }
            
            Button {
                self.showPicker.toggle()
            } label: {
                Text("选择照片")
            }.padding()
             
            
            if noBgimages.count > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 10, content: {
                        ForEach(self.noBgimages, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
                        }
                    })
                }
            }

        }
        .padding()
        .sheet(isPresented: $showPicker, content: {
            PhotoPickerView(pickedItem: $photoItem)
        })
        .onChange(of: self.photoItem) {
            if self.photoItem == nil {
                return
            }
            self.showPicker.toggle()
            print("开始：\(Date())")
            let startTime = CFAbsoluteTimeGetCurrent()
            
            Task {
                if let livePhoto = try? await self.photoItem!.loadTransferable(type: PHLivePhoto.self) {
                    await LiveGifKit.shared.getFrameImages(livePhoto: livePhoto, fps: self.fps, callback: { images in
                        var endTime = CFAbsoluteTimeGetCurrent() // 获取结束时间
                        print("获取到帧：\(Date()) 耗时: \(endTime - startTime)")
                        Task {
                            let noBgImages = await LiveGifKit.shared.removeBgColor(images: images)
                            let endTime01 = CFAbsoluteTimeGetCurrent()
                            print("获取到去背景帧：\(Date()) 耗时: \(endTime01 - endTime)")
                            self.gifUrl = await LiveGifKit.shared.createGif(images: noBgImages, frameRate: 1/Float(self.giffps))
                            let endTime02 = CFAbsoluteTimeGetCurrent()
                            print("gif 耗时: \(endTime02 - endTime01)")
                           
                            print("总耗时: \(endTime02 - startTime) 秒") // 输出耗时
                            self.totalTime = Double(Float(endTime02 - startTime))
                            self.photoItem = nil
                        }
                    })
                    print("图片数量: \(self.images.count)")
                }
                
            }
           
        }
    }
    
}

 
