import Foundation

struct OCRConfig: Sendable {
    var outputDir: URL?
    var recursive = false
    var jobs = 4
    var extensions = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "webp"]
    var overwrite = false
}
