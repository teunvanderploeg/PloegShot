import AppKit

enum AppResources {
    static let logo: NSImage? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let url = bundle.url(forResource: "Logo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
