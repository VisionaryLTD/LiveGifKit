//
//  WatermarkView.swift
//  GifDemo
//
//  Created by tangxiaojun on 2024/1/5.
//

import SwiftUI
import LiveGifKit

struct WatermarkView: View {
    @EnvironmentObject var vm: LiveGifViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("水印位置: \(self.vm.watermarkLocation.title)")
                .onTapGesture {
                    self.vm.showWatermarkLocation.toggle()
                }
                .contextMenu {
                    ForEach(DecoratorLocation.allCases, id: \.self) { location in
                        Button(location.title) {
                            self.vm.watermarkLocation = location
                        }
                    }
                }
            if !vm.imageWatermark {
                HStack {
                    Text("水印文字:")
                    TextField("test...", text: $vm.watermarkText)
                }
                HStack {
                    Text("文字颜色")
                    ColorPicker("", selection: $vm.selectedColor)
                    Spacer()
                }
            } else {
                Text("")
            }
        }
    }
}

#Preview {
    WatermarkView()
}
