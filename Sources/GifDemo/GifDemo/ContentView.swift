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
import Photos

struct ContentView: View {
    /// 相册Item
    @State var photoItem: PhotosPickerItem?
    
    /// 选择相册的flag
    @State var showPicker: Bool = false
    @State var images = [UIImage]()
    @State var gifUrl: URL?
    @State var fps: Double = 15
    @State var giffps: Double = 30
    @State var totalTime = 0.0
    @State var saveStatus = ""
    @State var gifTool: LiveGifTool?  = LiveGifTool()
    
    @State var watermarkText: String = ""
    @State private var selectedColor = Color.red
    @State var watermarkLocation: WatermarkLocation = .center
    @State var showWatermarkLocation = false
    @State var recommendImages = [UIImage]()
    @State var showRecommendUI = false
    var body: some View {
        VStack {
            Slider(value: $fps, in: 5...60, step: 5)
                .overlay(Text("LivePhoto每秒帧数(FPS): \(Int(fps))")
                    .foregroundColor(.primary)
                    .font(.headline)
                    .offset(x: 0, y: -20))
            
            Slider(value: $giffps, in: 5...60, step: 5)
                .overlay(Text("GIF每秒帧数(FPS): \(Int(giffps))")
                    .foregroundColor(.primary)
                    .font(.headline)
                    .offset(x: 0, y: -20))
            HStack {
                TextField("水印文字", text: $watermarkText)
                Spacer()
                ColorPicker("颜色", selection: $selectedColor)
                Text("位置: \(self.watermarkLocation.title)")
                    .onTapGesture {
                        self.showWatermarkLocation.toggle()
                    }
                    .contextMenu {
                        ForEach(WatermarkLocation.allCases, id: \.self) { location in
                            Button(location.title) {
                                self.watermarkLocation = location
                            }
                        }
                    }
            }
                        
            Spacer()
            if gifUrl?.absoluteString.count ?? 0 > 0 {
                KFAnimatedImage(gifUrl)
                    .scaledToFit()
                    .frame(width: 300)
                
                Text("总帧数: \(self.images.count)")
                Text("总耗时: \(self.totalTime)")
            }
            HStack {
                Button {
                    self.showPicker.toggle()
                } label: {
                    Text("选择照片")
                }.padding()
                
                Button {
                    self.gifTool?.cleanup()
                } label: {
                    Text("删除目录")
                }.padding()
                if self.recommendImages.count == -100 {
                    Text("推荐sfdf")
                }
                Button {
                    self.recommendImages = FetchPhoto.fetch()
                    print("推荐图片的个数: \(self.recommendImages.count)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        self.showRecommendUI.toggle()
                    })
                    
                    
                } label: {
                    Text("推荐")
                }
                .padding()
                .sheet(isPresented: $showRecommendUI) {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                        ]) {
                            ForEach(self.recommendImages, id: \.self) { image in
                               Image(uiImage: image)
                                   .resizable()
                                   .aspectRatio(contentMode: .fit)
                                   .background(.gray)
                           }
                        }
                    }
                }
                
            }
 
            Button {
                Task {
                    try? await self.gifTool?.save(method: .url(self.gifUrl!))
                }
            } label: {
                Text("保存照片\(self.saveStatus)")
            }.padding()
            
            Button {
                Task {
                    var waterConfig: WatermarkConfig? = nil
                    if self.watermarkText.count > 0 {
                        waterConfig = WatermarkConfig(text: self.watermarkText, textColor: UIColor(self.selectedColor), location: self.watermarkLocation)
                    }
                    let parameter = GifToolParameter(data: .images(frames: self.images), gifFPS: self.giffps, watermark: waterConfig)
                    let gif = try? await self.gifTool?.createGif(parameter: parameter)
                    self.gifUrl = gif?.url
                    self.totalTime = gif?.totalTime ?? 0
                    print("新的URL: \(String(describing: self.gifUrl))")
                }
            } label: {
                Text("重新生成")
            }.padding()
            
            if self.images.count > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 10, content: {
                        ForEach(self.images, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .background(.gray)
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
            Task {
                guard let photoItem = self.photoItem else { return }
                guard let livePhoto = try? await photoItem.loadTransferable(type: PHLivePhoto.self)  else { return }
                self.showPicker.toggle()
                do {
                    var waterConfig: WatermarkConfig? = nil
                    if self.watermarkText.count > 0 {
                        waterConfig = WatermarkConfig(text: self.watermarkText, textColor: UIColor(self.selectedColor), location: self.watermarkLocation)
                    }
                    
                    let parameter = GifToolParameter(data: .livePhoto(livePhoto: livePhoto, livePhotoFPS: self.fps), gifFPS: self.giffps, watermark: waterConfig)
                    let gif = try await self.gifTool?.createGif(parameter: parameter)

                    self.gifUrl = gif?.url
                    self.photoItem = nil
                    self.images = gif?.frames ?? []
                    self.totalTime = gif?.totalTime ?? 0
                    print("首次URL: \(String(describing: self.gifUrl))")
                } catch {
                    print("异常: \(error)")
                    self.photoItem = nil
                }
            }
        }
    }
}
