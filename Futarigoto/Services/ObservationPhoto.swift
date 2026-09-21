import UIKit

enum ObservationPhoto {
    private static let maxDimension: CGFloat = 1280
    private static let quality: CGFloat = 0.72

    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longest = max(size.width, size.height)
        if longest <= maxDimension, isJPEG(data) {
            return data
        }

        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    static func image(from data: Data?) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        return UIImage(data: data)
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }
}
