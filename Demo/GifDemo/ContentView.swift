//
//  ContentView.swift
//  GifDemo
//
//  Created by 汤小军 on 2023/12/10.
//

import SwiftUI
import PhotosUI
import LiveGifKit
import Photos
import SDWebImageSwiftUI

@MainActor
class PhotoPickerViewModel: ObservableObject {
    @Published var imageSelection: PhotosPickerItem? = nil {
        didSet {
            getLivePhoto(from: imageSelection)
             
        }
    }
    @Published var imageData: Data?
    @Published var livePhoto: PHLivePhoto?
    @Published var gif: GifResult?
    
    ///
    @Published var watermarkText: String = ""
    @Published var selectedColor = Color.red
    @Published var watermarkLocation: WatermarkLocation = .center
    @Published var fps: Double = 15
    @Published var giffps: Double = 30
    @Published var removeBg = false
    
    @Published var recommendImages = [UIImage]()
    @Published var showRecommendUI = false
    
    var gifTool: LiveGifTool?  = LiveGifTool()
    func getLivePhoto(from selection: PhotosPickerItem?) {
        guard let selection else {
            return
        }
        
        Task {
            self.livePhoto = try? await selection.loadTransferable(type: PHLivePhoto.self)
            self.imageData = try? await selection.loadTransferable(type: Data.self)
            
            await handleLivePhoto()
            
        }
    }
    
    func handleLivePhoto() async {
        guard let livePhoto = self.livePhoto else { return }
        do {
            self.gif = try await self.gifTool?.createGif(parameter: getGifParameter(livePhoto: livePhoto))
           
//            print("首次URL: \(String(describing: self.gif.gifUrl))")
        } catch {
            print("异常: \(error)")
           
        }
    }
    
    func getWaterConfig() -> WatermarkConfig? {
        var waterConfig: WatermarkConfig? = nil
        if self.watermarkText.count > 0 {
            waterConfig = WatermarkConfig(text: self.watermarkText, textColor: UIColor(self.selectedColor), location: self.watermarkLocation)
        }
        return waterConfig
    }
    
    func getGifParameter(livePhoto: PHLivePhoto) -> GifToolParameter {
        let parameter = GifToolParameter(data: .livePhoto(livePhoto: livePhoto, livePhotoFPS: self.fps), gifFPS: self.giffps, watermark: getWaterConfig(), removeBg: self.removeBg)
        return parameter
    }
    
    func getGifParameter(images: [UIImage]?) -> GifToolParameter {
        let parameter = GifToolParameter(data: .images(frames: images ?? []), gifFPS: self.giffps, watermark: getWaterConfig(), removeBg: self.removeBg)
        return parameter
    }
    
    func savePhoto() async {
        guard let url = self.gif?.url else { return }
        try? await self.gifTool?.save(method: .url(url))

    }
    
    func recommandPhoto() {
        self.recommendImages = FetchPhoto.fetch()
        print("推荐图片的个数: \(self.recommendImages.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.showRecommendUI.toggle()
        })
    }
    
}


struct ContentView: View {
 
    @StateObject var vm = PhotoPickerViewModel()
    
    /// 选择相册的flag
    @State var showPicker: Bool = false
    @State var showWatermarkLocation = false
    
    var body: some View {
        VStack {
            HStack {
                Slider(value: $vm.fps, in: 5...60, step: 5)
                    .overlay(Text("LP(FPS): \(Int(vm.fps))")
                        .foregroundColor(.primary)
                        .font(.headline)
                        .offset(x: 0, y: -20))
                Spacer()
                Toggle("切换", isOn: $vm.removeBg)
            }
          
            
            Slider(value: $vm.giffps, in: 5...60, step: 5)
                .overlay(Text("GIF(FPS): \(Int(vm.giffps))")
                    .foregroundColor(.primary)
                    .font(.headline)
                    .offset(x: 0, y: -20))
            HStack {
                TextField("水印文字", text: $vm.watermarkText)
                Spacer()
                ColorPicker("颜色", selection: $vm.selectedColor)
                Text("位置: \(self.vm.watermarkLocation.title)")
                    .onTapGesture {
                        self.showWatermarkLocation.toggle()
                    }
                    .contextMenu {
                        ForEach(WatermarkLocation.allCases, id: \.self) { location in
                            Button(location.title) {
                                self.vm.watermarkLocation = location
                            }
                        }
                    }
            }
                        
            Spacer()
            if let data = self.vm.gif?.data {
                AnimatedImage(data: data)
                    .purgeable(true)
                    .resizable()
                    .scaledToFit()
//                Text("总帧数: \(self.vm.gif?.frames.count)")
//                Text("总耗时: \(self.vm.gif?.totalTime)")
            }
            
            HStack {
            
                Button {
                    self.vm.gifTool?.cleanup()
                } label: {
                    Text("删除目录")
                }.padding()
                
                if self.vm.recommendImages.count == -100 {
                    Text("推荐sfdf")
                }
                Button {
                    self.vm.recommandPhoto()
                } label: {
                    Text("推荐")
                }
                .padding()
                .sheet(isPresented: $vm.showRecommendUI) {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                            GridItem(.adaptive(minimum: 120, maximum: 180)),
                        ]) {
                            ForEach(self.vm.recommendImages, id: \.self) { image in
                               Image(uiImage: image)
                                   .resizable()
                                   .aspectRatio(contentMode: .fit)
                                   .background(.yellow)
                           }
                        }
                    }
                }
            }
 
            Button {
                Task {
                    await vm.savePhoto()
                }
            } label: {
                Text("保存照片")
            }.padding()
            
            Button {
//                Task {
//                    if self.gifTool == nil {
//                        self.gifTool = LiveGifTool()
//                    }
//                   
//                    
//                    let gif = try? await self.gifTool?.createGif(parameter: getGifParameter(images: self.images))
//                    self.gifUrl = gif?.url
//                    self.gifData = gif?.data
//                    self.images = gif?.frames ?? []
//                    self.totalTime = gif?.totalTime ?? 0
//                    
//                    print("新的URL: \(String(describing: self.gifUrl))")
//                }
            } label: {
                Text("重新生成")
            }.padding()
            
            PhotosPicker(selection: $vm.imageSelection, matching: .images, preferredItemEncoding: .automatic, photoLibrary: .shared()) {
                 Text("打开相册")
                    .foregroundStyle(.red)
            }
        
            if let images = self.vm.gif?.frames, images.count > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 10, content: {
                        ForEach(images, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .background(.gray)
                                .frame(width: 300)
                        }
                    })
                }
            }
        }
        .padding()
    }
}
