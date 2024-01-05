//
//  GifDemoApp.swift
//  GifDemo
//
//  Created by 汤小军 on 2023/12/10.
//

import SwiftUI

@main
struct GifDemoApp: App {
    @StateObject var vm = LiveGifViewModel()
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(vm)
        }
    }
}
