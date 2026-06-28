//
//  DeskFitApp.swift
//  DeskFit
//
//  Created by Akash Kundu on 29/05/26.
//

import SwiftUI

@main
struct DeskFitApp: App {
    init() {
        // Register the local-notification delegate so taps deep-link correctly.
        NotificationService.shared.configure()
        // Activate the watchOS link (no-op when no Watch is paired).
        PhoneWatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .preferredColorScheme(.dark)
        }
    }
}
