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
        let appFonts = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? []
        print("UIAppFonts from Info.plist:", appFonts)
        let fontExistence = appFonts.map { font in
            let exists = Bundle.main.url(forResource: font, withExtension: nil) != nil
            return "\(font)=\(exists)"
        }
        print("UIAppFonts existence:", fontExistence)
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
