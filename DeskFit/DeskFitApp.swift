//
//  DeskFitApp.swift
//  DeskFit
//
//  Created by Akash Kundu on 29/05/26.
//

import SwiftUI

@main
struct DeskFitApp: App {
    var body: some Scene {
        WindowGroup {
            AppRouter()
                .preferredColorScheme(.dark)
        }
    }
}
