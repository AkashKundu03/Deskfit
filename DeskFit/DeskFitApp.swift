//
//  DeskFitApp.swift
//  DeskFit
//
//  Created by Akash Kundu on 29/05/26.
//

import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct DeskFitApp: App {
    var body: some Scene {
        WindowGroup {
            AppRouter()
                .preferredColorScheme(.dark)
                // Completes the Google Sign-In OAuth redirect. No-op until the
                // GoogleSignIn package + reversed-client-id URL scheme are added.
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
    }
}
