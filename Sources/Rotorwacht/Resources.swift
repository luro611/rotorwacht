import Foundation
import AppKit
import CoreText

/// Finds bundled files: in the .app (Contents/Resources) or, when run from a build folder, next to the sources.
enum Res {
    static func url(_ name: String, _ ext: String, in folder: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder) { return u }
        #if SWIFT_PACKAGE
        if let u = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: folder) { return u }
        #endif
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("\(folder)/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func image(_ name: String) -> NSImage? {
        guard let u = url(name, "png", in: "Images") else { return nil }
        return NSImage(contentsOf: u)
    }

    /// Registers the OTF fonts (Instrument Serif, Inter, Archivo, Geist Mono) for this process only.
    static func registerFonts() {
        let names = ["Inter-Regular", "Inter-Medium", "Archivo-Medium", "Archivo-SemiBold",
                     "InstrumentSerif-Regular", "InstrumentSerif-Italic", "GeistMono-Regular", "GeistMono-Medium"]
        for n in names {
            if let u = url(n, "otf", in: "Fonts") {
                CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
            }
        }
    }
}
