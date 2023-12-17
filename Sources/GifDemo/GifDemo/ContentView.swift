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
            }
 
            Button {
                Task {
                    do {
                        try await self.gifTool?.save(method: .url(self.gifUrl!))
                    } catch {
                        print("失败: \(error)")
                    }
                }
            } label: {
                Text("保存照片\(self.saveStatus)")
            }.padding()
            
            Button {
                Task {
                    do {
                        let gif = try await self.gifTool?.createGif(frames: self.images, gifFrameRate: self.giffps)
                        self.gifUrl = gif?.url
                        print("新的URL: \(String(describing: self.gifUrl))")
                    } catch {
                        print("失败: \(error)")
                    }
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
                                .frame(width: 300)
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
                print("开始：\(Date())")
                let startTime = CFAbsoluteTimeGetCurrent()
                do {
                    let gif = try await self.gifTool?.createGif(livePhoto: livePhoto, gifFrameRate: self.giffps)
                    let endTime = CFAbsoluteTimeGetCurrent()
                    self.gifUrl = gif?.url
                    self.photoItem = nil
                    self.images = gif?.frames ?? []
                    self.totalTime = endTime - startTime
                    print("首次URL: \(String(describing: self.gifUrl))")
                } catch {
                    print("异常: \(error)")
                }
            }
        }
    }
    
    func getRecent() {
        // 获取最近三十天的照片
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", Calendar.current.date(byAdding: .day, value: -30, to: Date())! as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        fetchResult.enumerateObjects { object, _, _ in
            guard let asset = object as? PHAsset else { return }
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFit, options: requestOptions) { image, _ in
                guard let image = image else { return }
                print("哈哈哈哈: \(image)")
                //                self.iamges.append(image)
                // 在这里处理您获取的照片，比如将其添加到一个数组中等等。
            }
        }
    }
}
