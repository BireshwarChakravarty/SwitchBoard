import AppKit
import CoreImage.CIFilterBuiltins

/// QR codes for the remote's address, so the iPhone's camera can open it.
enum QRCode {
    /// A black-on-white QR code for `text`, `scale` pixels per module, or nil
    /// if Core Image can't make one.
    static func image(for text: String, scale: CGFloat = 8) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
