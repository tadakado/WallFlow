import AppKit
import SwiftUI

struct FocalImageView: View {
    let image: NSImage
    let focusPoint: CGPoint
    let detectionRegion: CGRect?

    init(image: NSImage, focusPoint: CGPoint, detectionRegion: CGRect? = nil) {
        self.image = image
        self.focusPoint = focusPoint
        self.detectionRegion = detectionRegion
    }

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let imageSize = pixelSize(for: image)
            let scale = max(
                containerSize.width / max(imageSize.width, 1),
                containerSize.height / max(imageSize.height, 1)
            )
            let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let overflow = CGSize(
                width: max(0, scaledSize.width - containerSize.width),
                height: max(0, scaledSize.height - containerSize.height)
            )
            let offset = imageOffset(scaledSize: scaledSize, overflow: overflow)
            let imageRect = CGRect(
                x: (containerSize.width - scaledSize.width) / 2 + offset.width,
                y: (containerSize.height - scaledSize.height) / 2 + offset.height,
                width: scaledSize.width,
                height: scaledSize.height
            )

            Canvas { context, _ in
                context.draw(Image(nsImage: image), in: imageRect)

                if let detectionRegion {
                    let regionRect = displayRect(for: detectionRegion, in: imageRect)
                    context.stroke(
                        Path(roundedRect: regionRect, cornerRadius: 3),
                        with: .color(.yellow),
                        lineWidth: 3
                    )
                    context.stroke(
                        Path(roundedRect: regionRect.insetBy(dx: -2, dy: -2), cornerRadius: 5),
                        with: .color(.black.opacity(0.75)),
                        lineWidth: 1
                    )
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
        }
        .clipped()
    }

    private func pixelSize(for image: NSImage) -> CGSize {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image.size
        }

        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private func imageOffset(scaledSize: CGSize, overflow: CGSize) -> CGSize {
        let focusX = clamp(focusPoint.x, min: 0, max: 1)
        let focusY = clamp(focusPoint.y, min: 0, max: 1)

        let desiredX = (0.5 - focusX) * scaledSize.width
        let desiredY = (0.5 - focusY) * scaledSize.height

        return CGSize(
            width: clamp(desiredX, min: -overflow.width / 2, max: overflow.width / 2),
            height: clamp(desiredY, min: -overflow.height / 2, max: overflow.height / 2)
        )
    }

    private func displayRect(for normalizedRect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}
