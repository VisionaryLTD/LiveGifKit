//
//  GifDemoApp.swift
//  GifDemo
//
//  Created by 汤小军 on 2023/12/10.
//

import SwiftUI

@main
struct GifDemoApp: App {
    @State private var viewModel = LiveGIFDemoViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(viewModel)
                .environment(viewModel.session)
                .task {
                    viewModel.warmUp()
                }
        }
    }
}
