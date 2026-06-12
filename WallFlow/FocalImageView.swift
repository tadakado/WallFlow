import AppKit
import SwiftUI

enum ImageScalingMode {
    case fit
    case fill
}

struct DetectionRegion {
    let rect: CGRect
    let detectorName: String
    let detectorConfidence: Float?
    let humanConfidence: Float?
    let nonHumanConfidence: Float?
    let usesHumanFocus: Bool
    let participatesInFocus: Bool
    let rejectionReason: String?
}

struct FocalImageView: NSViewRepresentable {
    let image: CGImage
    let focusPoint: CGPoint
    let detectionRegions: [DetectionRegion]
    let scalingMode: ImageScalingMode

    init(
        image: CGImage,
        focusPoint: CGPoint,
        detectionRegions: [DetectionRegion] = [],
        scalingMode: ImageScalingMode = .fill
    ) {
        self.image = image
        self.focusPoint = focusPoint
        self.detectionRegions = detectionRegions
        self.scalingMode = scalingMode
    }

    func makeNSView(context: Context) -> DrawingView {
        let view = DrawingView()
        view.imageScaling = scalingMode
        view.image = image
        view.focusPoint = focusPoint
        view.detectionRegions = detectionRegions
        return view
    }

    func updateNSView(_ nsView: DrawingView, context: Context) {
        nsView.image = image
        nsView.focusPoint = focusPoint
        nsView.detectionRegions = detectionRegions
        nsView.imageScaling = scalingMode
    }

    final class DrawingView: NSView {
        var image: CGImage? {
            didSet { needsDisplay = true }
        }

        var focusPoint = CGPoint(x: 0.5, y: 0.5) {
            didSet { needsDisplay = true }
        }

        var detectionRegions: [DetectionRegion] = [] {
            didSet { needsDisplay = true }
        }

        var imageScaling: ImageScalingMode = .fill {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            autoreleasepool {
                NSColor.black.setFill()
                bounds.fill()

                guard let image else {
                    return
                }

                let imageRect = displayImageRect(for: image)
                let nsImage = NSImage(
                    cgImage: image,
                    size: CGSize(width: image.width, height: image.height)
                )
                nsImage.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)

                for detectionRegion in detectionRegions {
                    drawDetectionRegion(detectionRegion, in: imageRect)
                }
            }
        }

        private func displayImageRect(for image: CGImage) -> CGRect {
            let containerSize = bounds.size
            let imageSize = CGSize(width: image.width, height: image.height)
            let widthScale = containerSize.width / max(imageSize.width, 1)
            let heightScale = containerSize.height / max(imageSize.height, 1)
            let scale = imageScaling == .fit
                ? min(widthScale, heightScale)
                : max(widthScale, heightScale)
            let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let centeredRect = CGRect(
                x: (containerSize.width - scaledSize.width) / 2,
                y: (containerSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )

            guard imageScaling == .fill else {
                return centeredRect
            }

            let overflow = CGSize(
                width: max(0, scaledSize.width - containerSize.width),
                height: max(0, scaledSize.height - containerSize.height)
            )
            let offset = imageOffset(scaledSize: scaledSize, overflow: overflow)

            return centeredRect.offsetBy(dx: offset.width, dy: offset.height)
        }

        private func imageOffset(scaledSize: CGSize, overflow: CGSize) -> CGSize {
            let focusX = clamp(focusPoint.x, min: 0, max: 1)
            let focusY = clamp(focusPoint.y, min: 0, max: 1)

            let desiredX = (0.5 - focusX) * scaledSize.width
            let desiredY = (focusY - 0.5) * scaledSize.height

            return CGSize(
                width: clamp(desiredX, min: -overflow.width / 2, max: overflow.width / 2),
                height: clamp(desiredY, min: -overflow.height / 2, max: overflow.height / 2)
            )
        }

        private func drawDetectionRegion(_ detectionRegion: DetectionRegion, in imageRect: CGRect) {
            let normalizedRect = detectionRegion.rect
            let regionRect = CGRect(
                x: imageRect.minX + normalizedRect.minX * imageRect.width,
                y: imageRect.minY + (1 - normalizedRect.maxY) * imageRect.height,
                width: normalizedRect.width * imageRect.width,
                height: normalizedRect.height * imageRect.height
            )

            NSColor.black.withAlphaComponent(0.75).setStroke()
            let outerPath = NSBezierPath(roundedRect: regionRect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
            outerPath.lineWidth = 1
            outerPath.stroke()

            regionColor(for: detectionRegion).setStroke()
            let innerPath = NSBezierPath(roundedRect: regionRect, xRadius: 3, yRadius: 3)
            innerPath.lineWidth = 3
            innerPath.stroke()

            drawLabel(for: detectionRegion, beside: regionRect)
        }

        private func regionColor(for detectionRegion: DetectionRegion) -> NSColor {
            if !detectionRegion.participatesInFocus {
                return NSColor.systemGray
            }

            if detectionRegion.usesHumanFocus {
                return NSColor.systemGreen
            }

            if detectionRegion.rejectionReason != nil {
                return NSColor.systemOrange
            }

            return NSColor.systemYellow
        }

        private func drawLabel(for detectionRegion: DetectionRegion, beside regionRect: CGRect) {
            let text = labelText(for: detectionRegion)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let maxLabelWidth = max(96, min(150, bounds.width - 12))
            let textSize = attributedText.boundingRect(
                with: CGSize(width: maxLabelWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
            let labelSize = CGSize(width: ceil(textSize.width) + 14, height: ceil(textSize.height) + 10)
            let labelOrigin = labelOrigin(for: labelSize, beside: regionRect)
            let labelRect = CGRect(origin: labelOrigin, size: labelSize)

            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()

            let borderColor = regionColor(for: detectionRegion).withAlphaComponent(0.9)
            borderColor.setStroke()
            let borderPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
            borderPath.lineWidth = 1
            borderPath.stroke()

            attributedText.draw(
                with: labelRect.insetBy(dx: 7, dy: 5),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }

        private func labelOrigin(for labelSize: CGSize, beside regionRect: CGRect) -> CGPoint {
            let preferredX = regionRect.minX
            let preferredY = regionRect.minY - labelSize.height - 6
            let fallbackY = regionRect.maxY + 6
            let minX = bounds.minX + 6
            let maxX = max(minX, bounds.maxX - labelSize.width - 6)
            let minY = bounds.minY + 6
            let maxY = max(minY, bounds.maxY - labelSize.height - 6)
            let candidateY = preferredY >= minY ? preferredY : fallbackY

            return CGPoint(
                x: clamp(preferredX, min: minX, max: maxX),
                y: clamp(candidateY, min: minY, max: maxY)
            )
        }

        private func labelText(for detectionRegion: DetectionRegion) -> String {
            var lines = [detectionRegion.detectorName]

            if let detectorConfidence = detectionRegion.detectorConfidence {
                lines[0] += " \(percentText(detectorConfidence))"
            }

            if detectionRegion.humanConfidence != nil
                || detectionRegion.nonHumanConfidence != nil {
                lines.append(
                    "H \(percentText(detectionRegion.humanConfidence))"
                        + " N \(percentText(detectionRegion.nonHumanConfidence))"
                )
            }

            if !detectionRegion.participatesInFocus {
                lines.append("skip: lower confidence")
            } else if detectionRegion.usesHumanFocus {
                lines.append("use: human")
            } else if let rejectionReason = detectionRegion.rejectionReason {
                lines.append("skip: \(rejectionReason)")
            } else {
                lines.append("use: fallback")
            }

            return lines.joined(separator: "\n")
        }

        private func percentText(_ value: Float) -> String {
            "\(Int((value * 100).rounded()))%"
        }

        private func percentText(_ value: Float?) -> String {
            value.map(percentText) ?? "--"
        }

        private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
            Swift.min(Swift.max(value, minValue), maxValue)
        }
    }
}
