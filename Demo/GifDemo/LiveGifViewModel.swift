//
//  LiveGifViewModel.swift
//  GifDemo
//
//  Created by tangxiaojun on 2024/1/5.
//

import Foundation
import _PhotosUI_SwiftUI
import LiveGifKit
import SwiftUI

@MainActor
class LiveGifViewModel: ObservableObject {
    var gifTool: LiveGifTool?  = LiveGifTool()
    
    /// 相册Item
   
    @Published var photoItem: PhotosPickerItem?
    @Published var fps: Double = 15
    @Published var giffps: Double = 30
    @Published var removeBg = false {
        didSet {
            self.requestData()
        }
    }
    @Published var isLivePhoto = false
    @Published var isShowStaticImage = true {
        didSet {
            self.requestData()
        }
    }
    @Published var imageWatermark = false
    @Published var saveStatus = ""
    
    /// 水印功能
    @Published var watermarkText: String = ""
    @Published var selectedColor = Color.red
    @Published var watermarkLocation: WatermarkLocation = .center
    @Published var showWatermarkLocation = false
    
    /// 推荐功能
    @Published var recommendImages = [UIImage]()
    @Published var showRecommendUI = false
    @Published var showFramesUI = false
    ///
    var photoImage: UIImage?
    var livePhoto: PHLivePhoto?
    @Published var gifResult: GifResult?
    
    var task: Task<(), Never>? = nil
    
    init() {
        Task {
           try? await LiveGifTool().preheating()
        }
        
    }
    
    func requestPickerItem() {
        self.gifTool = nil
        self.gifTool = LiveGifTool()
        guard let photoItem = photoItem else { return }
         
        let task = Task {
            if let photoData = try? await photoItem.loadTransferable(type: Data.self) {
                self.photoImage = UIImage(data: photoData)
            }
            if let livePhoto = try? await photoItem.loadTransferable(type: PHLivePhoto.self) {
                self.livePhoto = livePhoto
            }
             
            self.requestData()
        }
        self.task = task
    }
    
    func requestData() {
        self.gifTool = nil
        self.gifTool = LiveGifTool()
        cancelTask()
        if isShowStaticImage {
            self.requestImages()
        } else {
            self.requestLivePhoto()
        }
    }
    
    func requestLivePhoto() {
        guard let livePhoto = livePhoto else { return }
        let parameter = GifToolParameter(data: .livePhoto(livePhoto: livePhoto, livePhotoFPS: self.fps), gifFPS: self.giffps, watermark: getWaterConfig(), removeBg: self.removeBg)
    
        let task = Task {
            do {
                self.gifResult = try await self.gifTool?.createGif(parameter: parameter)
                self.photoItem = nil
            } catch {
                print("requestPickerItem: \(error)")
                self.photoItem = nil
            }
        }
        self.task = task
    }
    

    func requestImages() {
        if self.getRequestImages().count == 0 {
            return
        }
        self.gifTool = nil
        self.gifTool = LiveGifTool()
      
        let parameter = GifToolParameter(data: .images(frames: getRequestImages(), adjustOrientation: self.isShowStaticImage == true), gifFPS: self.giffps, watermark: getWaterConfig(), removeBg: self.removeBg)

        let task = Task {
            do {
              let result = try await self.gifTool?.createGif(parameter: parameter)
              self.gifResult = result
              self.photoItem = nil
            } catch {
                self.photoItem = nil
                print("requestImages error: \(error)")
            }
        }
        self.task = task
    }
    
    func getWaterConfig() -> WatermarkConfig? {
        var waterConfig: WatermarkConfig? = nil
        if !imageWatermark, self.watermarkText.count > 0 {
            waterConfig = WatermarkConfig(type: .text(text: self.watermarkText, textColor: UIColor(self.selectedColor)), location: self.watermarkLocation)
        } else if imageWatermark, let img = UIImage(named: "test") {
            waterConfig = WatermarkConfig(type: .image(image: img, width: 100), location: self.watermarkLocation)
        }
        return waterConfig
    }
    
    func getRequestImages() -> [UIImage] {
        if self.isShowStaticImage {
            guard let photoImage = self.photoImage else { return [] }
            return [photoImage]
        }
        return self.gifResult?.frames ?? []
    }
    
    func savePhoto() {
        cancelTask()
        let task = Task {
            guard let url = gifResult?.url else { return  }
            try? await self.gifTool?.save(method: .url(url))
        }
        self.task = task
    }
    
    func cleanUp() {
        try? self.gifTool?.cleanup()
        self.gifTool = nil
    }
    
    func cancelTask() {
        if let task = self.task, task.isCancelled == false {
            print("任务过程中。。取消任务")
            task.cancel()
        }
    }
}
