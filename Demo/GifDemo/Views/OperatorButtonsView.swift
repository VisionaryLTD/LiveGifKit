//
//  OperatorButtonsView.swift
//  GifDemo
//
//  Created by tangxiaojun on 2024/1/5.
//

import SwiftUI
import LiveGifKit

struct OperatorButtonsView: View {
    @EnvironmentObject var vm: LiveGifViewModel
    
    var body: some View {
        HStack {
            Button {
                self.vm.cleanUp()
            } label: {
                Text("删除目录")
            }.padding()
            if self.vm.recommendImages.count == -100 {
                Text("推荐sfdf")
            }
            
            Button {
                self.vm.recommendImages = FetchPhoto.fetch()
                print("推荐图片的个数: \(self.vm.recommendImages.count)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                    self.vm.showRecommendUI.toggle()
                })
            } label: {
                Text("智能推荐")
            }
            .padding()
            .sheet(isPresented: $vm.showRecommendUI) {
                ImageListView(uiImages: self.vm.recommendImages)
            }
            
            Button {
                self.vm.savePhoto()
            } label: {
                Text("保存照片\(self.vm.saveStatus)")
            }.padding()
            
            Button {
                self.vm.requestData()
            } label: {
                Text("重新生成")
            }.padding()
        }
    }
}

 
