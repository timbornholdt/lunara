//
//  LunaraApp.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/8/26.
//

import SwiftUI

@main
struct LunaraApp: App {
    init() {
        #if DEBUG
        let playfairFonts = UIFont.familyNames
            .filter { $0.localizedCaseInsensitiveContains("Playfair") }
            .flatMap { family in
                UIFont.fontNames(forFamilyName: family).map { "\(family): \($0)" }
            }
        print("Playfair fonts registered:", playfairFonts)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
