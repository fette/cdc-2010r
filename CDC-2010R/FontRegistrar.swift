//
//  FontRegistrar.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/23.
//

import CoreText
import Foundation

enum FontRegistrar {
    static func register() -> String? {
        guard let url = Bundle.main.url(forResource: "led16sgmnt2-Italic", withExtension: "ttf") else {
            return nil
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }
        let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        return name
    }
}
