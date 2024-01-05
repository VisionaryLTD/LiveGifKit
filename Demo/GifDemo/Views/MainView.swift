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

struct MainView: View {
   
    @EnvironmentObject var vm: LiveGifViewModel
   
    var body: some View {
        VStack {
            HStack {
                VStack {
                    Toggle("去背景", isOn: $vm.removeBg)
                    Toggle("相册实况/静态图", isOn: $vm.isLivePhoto)
                    Toggle("输出静图", isOn: $vm.isShowStaticImage)
                    Toggle("图片水印", isOn: $vm.imageWatermark)
                }
            }
            HStack {
                Text("LP(FPS): \(Int(vm.fps))")
                Slider(value: $vm.fps, in: 5...60, step: 5) { isEditing in
                    if !isEditing {
                        self.vm.requestData()
                    }
                }
            }
            HStack {
                Text("GIF(FPS): \(Int(vm.giffps))")
                Slider(value: $vm.giffps, in: 5...60, step: 5) { isEditing in
                    if !isEditing {
                        self.vm.requestData()
                    }
                }
            }
            
            WatermarkView()
            Divider()
            Spacer()
            
            if let data = self.vm.gifResult?.data {
                HStack {
                    AnimatedImage(data: data)
                        .purgeable(true)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300)
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("总帧数: \(self.vm.gifResult?.frames.count ?? 0)")
                        Text("总耗时: \(self.vm.gifResult?.totalTime ?? 0)")
                        Button("查看帧") {
                            self.vm.showFramesUI.toggle()
                        }
                        .sheet(isPresented: $vm.showFramesUI) {
                            ImageListView(uiImages: self.vm.gifResult?.frames ?? [])
                        }
                    }
                    .frame(minWidth: 150)
                }
            }
           
            PhotosPicker("选择照片", selection: $vm.photoItem, matching: self.vm.isLivePhoto ? .livePhotos : .images)
                .photosPickerStyle(.presentation)
                .photosPickerDisabledCapabilities(.selectionActions)
                .ignoresSafeArea(edges: .top)
                
          
            /// 操作：删除目录、保存相册、重新生成、智能推荐
            OperatorButtonsView()
        }
        .padding()
        .onChange(of: self.vm.photoItem) {oldValue, newValue in
            if newValue != nil {
                self.vm.requestPickerItem()
            }
        }
    }
}
