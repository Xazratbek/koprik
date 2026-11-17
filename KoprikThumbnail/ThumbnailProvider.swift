import AppKit
import KoprikKit
import QuickLookThumbnailing

/// Gives Windows executables their own icon in Finder, instead of a blank page.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        guard let data = PEFile(url: request.fileURL)?.iconFileData,
              let icon = NSImage(data: data), icon.isValid else {
            handler(nil, nil)
            return
        }
        let size = request.maximumSize
        let side = min(size.width, size.height)
        let canvas = CGSize(width: side, height: side)
        handler(QLThumbnailReply(contextSize: canvas) { () -> Bool in
            icon.draw(in: CGRect(origin: .zero, size: canvas), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }, nil)
    }
}
