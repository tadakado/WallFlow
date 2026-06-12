import AppKit
import Combine
import CoreML
import ImageIO
import SwiftUI
import Vision

@MainActor
final class ImageSlideshowViewModel: ObservableObject {
    @Published var intervalSeconds: Double {
        didSet {
            UserDefaults.standard.set(intervalSeconds, forKey: UserDefaultsKey.intervalSeconds)
            restartTimerIfNeeded()
        }
    }

    @Published private(set) var currentImage: CGImage?
    @Published private(set) var currentImageRevision = 0
    @Published private(set) var currentFocusPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var currentDetectionRegions: [DetectionRegion] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var isRunning = false
    @Published var displayMode: ImageDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: UserDefaultsKey.displayMode)
        }
    }
    @Published var showsDetectionRegionOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showsDetectionRegionOverlay, forKey: UserDefaultsKey.showsDetectionRegionOverlay)
        }
    }
    @Published var showsError = false
    @Published private(set) var errorMessage = ""

    private var imageURLs: [URL] = []
    private var history: [URL] = []
    private var historyIndex: Int?
    private var timer: Timer?
    private var securityScopedURL: URL?

    private static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    private static let recentExclusionCount = 10
    private static let animeFaceModelName = "AnimeFaceDetector"
    private static let animeCharacterClassifierModelName = "AnimeCharacterClassifier"
    private static let animeFaceConfidenceThreshold: VNConfidence = 0.3
    private static let minimumHumanFaceConfidence: VNConfidence = 0.03
    private static let nonHumanFaceConfidenceThreshold: VNConfidence = 0.3
    private static let minimumNonHumanAdvantage: VNConfidence = 0.15
    private static let maxDisplayImagePixelDimension = 2560
    private static let maxAnalysisImagePixelDimension = 1024
    private static let faceClassificationPadding: CGFloat = 0.35

    private lazy var animeFaceVisionModel: VNCoreMLModel? = {
        guard let modelURL = modelURL(named: Self.animeFaceModelName) else {
            return nil
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            return try VNCoreMLModel(for: mlModel)
        } catch {
            return nil
        }
    }()

    private lazy var animeCharacterClassifierVisionModel: VNCoreMLModel? = {
        guard let modelURL = modelURL(named: Self.animeCharacterClassifierModelName) else {
            return nil
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            return try VNCoreMLModel(for: mlModel)
        } catch {
            return nil
        }
    }()

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: UserDefaultsKey.intervalSeconds)
        intervalSeconds = savedInterval > 0 ? savedInterval : 5

        let savedDisplayMode = UserDefaults.standard.string(forKey: UserDefaultsKey.displayMode)
        displayMode = ImageDisplayMode(rawValue: savedDisplayMode ?? "") ?? .fit

        if UserDefaults.standard.object(forKey: UserDefaultsKey.showsDetectionRegionOverlay) == nil {
            showsDetectionRegionOverlay = false
        } else {
            showsDetectionRegionOverlay = UserDefaults.standard.bool(forKey: UserDefaultsKey.showsDetectionRegionOverlay)
        }

        restoreBookmarkedFolder()
    }

    deinit {
        timer?.invalidate()
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var canStart: Bool {
        !imageURLs.isEmpty
    }

    var canGoPrevious: Bool {
        guard let historyIndex else {
            return false
        }

        return historyIndex > 0
    }

    var canGoNext: Bool {
        !imageURLs.isEmpty
    }

    var folderDisplayName: String {
        guard let folderURL else {
            return "フォルダ未選択"
        }

        return folderURL.path
    }

    var placeholderText: String {
        if folderURL == nil {
            return "フォルダを選択してください"
        }

        if imageURLs.isEmpty {
            return "対応画像が見つかりません"
        }

        return "開始すると画像を表示します"
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "画像フォルダを選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        saveBookmark(for: url)
        useFolder(url)
    }

    func toggleRunning() {
        isRunning ? stop() : start()
    }

    func normalizeInterval() {
        intervalSeconds = max(1, intervalSeconds.rounded())
    }

    func showPreviousImage() {
        guard let index = historyIndex, index > 0 else {
            return
        }

        showImageFromHistory(at: index - 1)
        restartTimerIfNeeded()
    }

    func showNextImage() {
        showNextRandomImage()
        restartTimerIfNeeded()
    }

    private func start() {
        guard canStart else {
            showError("選択フォルダ内に jpg, jpeg, png, heic 画像がありません。")
            return
        }

        normalizeInterval()
        isRunning = true
        showNextRandomImage()
        restartTimerIfNeeded()
    }

    private func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func restartTimerIfNeeded() {
        timer?.invalidate()
        timer = nil

        guard isRunning else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.showNextRandomImage()
            }
        }
    }

    private func showNextRandomImage() {
        guard let imageURL = nextRandomImageURL() else {
            stop()
            currentImage = nil
            return
        }

        guard setCurrentImage(from: imageURL) else {
            removeUnavailableImage(imageURL)
            showNextRandomImage()
            return
        }

        appendToHistory(imageURL)
    }

    private func useFolder(_ url: URL) {
        stopAccessingCurrentFolder()

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        securityScopedURL = didStartAccessing ? url : nil
        folderURL = url
        reloadImages()
        currentImage = nil
        history = []
        historyIndex = nil
    }

    private func reloadImages() {
        guard let folderURL else {
            imageURLs = []
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            imageURLs = contents.filter { url in
                Self.supportedExtensions.contains(url.pathExtension.lowercased())
            }
            history.removeAll { !imageURLs.contains($0) }
            if history.isEmpty {
                historyIndex = nil
                currentImage = nil
            } else if let index = historyIndex, !history.indices.contains(index) {
                historyIndex = history.indices.last
            }
        } catch {
            imageURLs = []
            history = []
            historyIndex = nil
            currentImage = nil
            showError("フォルダ内のファイル一覧を取得できませんでした。")
        }
    }

    private func nextRandomImageURL() -> URL? {
        guard !imageURLs.isEmpty else {
            return nil
        }

        if imageURLs.count == 1 {
            return imageURLs[0]
        }

        let recentURLs = recentHistoryURLs(limit: Self.recentExclusionCount)
        let candidatesExcludingRecent = imageURLs.filter { !recentURLs.contains($0) }

        if let imageURL = candidatesExcludingRecent.randomElement() {
            return imageURL
        }

        let currentURL = historyIndex.flatMap { history.indices.contains($0) ? history[$0] : nil }
        let candidatesExcludingCurrent = imageURLs.filter { $0 != currentURL }
        return candidatesExcludingCurrent.randomElement() ?? imageURLs.randomElement()
    }

    private func recentHistoryURLs(limit: Int) -> Set<URL> {
        guard let historyIndex else {
            return []
        }

        let startIndex = max(0, historyIndex - limit + 1)
        return Set(history[startIndex...historyIndex])
    }

    private func showImageFromHistory(at index: Int) {
        guard history.indices.contains(index) else {
            return
        }

        let imageURL = history[index]
        guard setCurrentImage(from: imageURL) else {
            removeUnavailableImage(imageURL)
            return
        }

        historyIndex = index
    }

    private func setCurrentImage(from imageURL: URL) -> Bool {
        autoreleasepool {
            guard let displayImage = loadImage(
                from: imageURL,
                maxPixelDimension: Self.maxDisplayImagePixelDimension
            ) else {
                return false
            }

            let analysisImage = loadImage(
                from: imageURL,
                maxPixelDimension: Self.maxAnalysisImagePixelDimension
            ) ?? displayImage
            let focusResult = detectFocusPoint(in: analysisImage)

            if let focusResult {
                currentFocusPoint = focusResult.point
                currentDetectionRegions = focusResult.regions
            } else {
                currentFocusPoint = CGPoint(x: 0.5, y: 0.5)
                currentDetectionRegions = []
            }

            currentImage = displayImage
            currentImageRevision += 1
            return true
        }
    }

    private func loadImage(from imageURL: URL, maxPixelDimension: Int) -> CGImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions)
    }

    private func detectFocusPoint(in image: CGImage) -> FocusDetectionResult? {
        if let faceFocus = detectFaceFocus(in: image) {
            return FocusDetectionResult(
                point: faceFocus.point,
                regions: faceFocus.regions
            )
        }

        if let animeFaceFocus = detectAnimeFaceFocus(in: image) {
            return FocusDetectionResult(
                point: animeFaceFocus.point,
                regions: animeFaceFocus.regions
            )
        }

        return nil
    }

    private func modelURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlpackage")
    }

    private func detectFaceFocus(in cgImage: CGImage) -> DetectedFocus? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let faces = request.results, !faces.isEmpty else {
            return nil
        }

        return DetectedFocus(
            candidates: faces.map {
                DetectionCandidate(
                    boundingBox: $0.boundingBox,
                    detectorName: "Vision",
                    detectorConfidence: $0.confidence
                )
            },
            classifications: detectCharacterClassifications(
                in: cgImage,
                boundingBoxes: faces.map(\.boundingBox)
            )
        )
    }

    private func detectAnimeFaceFocus(in cgImage: CGImage) -> DetectedFocus? {
        guard let animeFaceVisionModel else {
            return nil
        }

        let request = VNCoreMLRequest(model: animeFaceVisionModel)
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let detectedFaces = request.results?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .filter { $0.confidence >= Self.animeFaceConfidenceThreshold }

        guard let detectedFaces, !detectedFaces.isEmpty else {
            return nil
        }

        let focusIndexes = topConfidenceHalfIndexes(of: detectedFaces)

        return DetectedFocus(
            candidates: detectedFaces.enumerated().map { index, observation in
                DetectionCandidate(
                    boundingBox: observation.boundingBox,
                    detectorName: "AnimeFace",
                    detectorConfidence: observation.confidence,
                    participatesInFocus: focusIndexes.contains(index)
                )
            },
            classifications: detectCharacterClassifications(
                in: cgImage,
                boundingBoxes: detectedFaces.map(\.boundingBox)
            )
        )
    }

    private func topConfidenceHalfIndexes(
        of observations: [VNRecognizedObjectObservation]
    ) -> Set<Int> {
        let keepCount = max(1, Int(ceil(Double(observations.count) * 0.5)))
        return Set(observations.indices
            .sorted { observations[$0].confidence > observations[$1].confidence }
            .prefix(keepCount)
        )
    }

    private func detectCharacterClassifications(in cgImage: CGImage, boundingBoxes: [CGRect]) -> [CharacterClassification?] {
        guard let animeCharacterClassifierVisionModel else {
            return Array(repeating: nil, count: boundingBoxes.count)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return boundingBoxes.map { boundingBox in
            let request = VNCoreMLRequest(model: animeCharacterClassifierVisionModel)
            request.imageCropAndScaleOption = .centerCrop
            request.regionOfInterest = paddedRegionOfInterest(for: boundingBox)

            do {
                try handler.perform([request])
            } catch {
                return nil
            }

            return characterClassification(from: request.results)
        }
    }

    private func paddedRegionOfInterest(for boundingBox: CGRect) -> CGRect {
        let insetX = -boundingBox.width * Self.faceClassificationPadding
        let insetY = -boundingBox.height * Self.faceClassificationPadding
        let paddedRect = boundingBox.insetBy(dx: insetX, dy: insetY)
        let x = clamp(paddedRect.minX, min: 0, max: 1)
        let y = clamp(paddedRect.minY, min: 0, max: 1)
        let maxX = clamp(paddedRect.maxX, min: 0, max: 1)
        let maxY = clamp(paddedRect.maxY, min: 0, max: 1)

        return CGRect(
            x: x,
            y: y,
            width: max(maxX - x, 0.001),
            height: max(maxY - y, 0.001)
        )
    }

    private func characterClassification(from results: [VNObservation]?) -> CharacterClassification? {
        let classifications = results?.compactMap { $0 as? VNClassificationObservation } ?? []
        let humanConfidence = classifications
            .filter { isHumanLabel($0.identifier) }
            .map(\.confidence)
            .max()
        let nonHumanConfidence = classifications
            .filter { isNonHumanLabel($0.identifier) }
            .map(\.confidence)
            .max() ?? 0

        let humanScore = humanConfidence ?? 0

        if nonHumanConfidence >= Self.nonHumanFaceConfidenceThreshold,
           nonHumanConfidence - humanScore >= Self.minimumNonHumanAdvantage {
            return CharacterClassification(
                humanConfidence: humanConfidence,
                nonHumanConfidence: nonHumanConfidence,
                usesHumanFocus: false,
                rejectionReason: "non_human"
            )
        }

        guard humanScore >= Self.minimumHumanFaceConfidence else {
            return CharacterClassification(
                humanConfidence: humanConfidence,
                nonHumanConfidence: nonHumanConfidence,
                usesHumanFocus: false,
                rejectionReason: nil
            )
        }

        let usesHumanFocus = humanScore > nonHumanConfidence
        return CharacterClassification(
            humanConfidence: humanConfidence,
            nonHumanConfidence: nonHumanConfidence,
            usesHumanFocus: usesHumanFocus,
            rejectionReason: usesHumanFocus ? nil : "non_human"
        )
    }

    private func isHumanLabel(_ label: String) -> Bool {
        let normalizedLabel = label.lowercased()
        return normalizedLabel == "human"
            || normalizedLabel == "person"
            || normalizedLabel == "people"
    }

    private func isNonHumanLabel(_ label: String) -> Bool {
        let normalizedLabel = label.lowercased()
        return normalizedLabel == "non_human"
            || normalizedLabel == "non-human"
            || normalizedLabel == "no_humans"
            || normalizedLabel == "animal"
            || normalizedLabel == "animal_focus"
            || normalizedLabel == "creature"
            || normalizedLabel == "mascot"
            || normalizedLabel == "monster"
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func appendToHistory(_ imageURL: URL) {
        if let index = historyIndex, index < history.count - 1 {
            history.removeSubrange((index + 1)..<history.count)
        }

        if history.last != imageURL {
            history.append(imageURL)
        }

        historyIndex = history.indices.last
    }

    private func removeUnavailableImage(_ imageURL: URL) {
        imageURLs.removeAll { $0 == imageURL }
        history.removeAll { $0 == imageURL }

        if imageURLs.isEmpty {
            historyIndex = nil
            currentImage = nil
            stop()
            showError("読み込める画像がなくなりました。")
            return
        }

        historyIndex = history.indices.last
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.folderBookmark)
        } catch {
            showError("フォルダのアクセス権を保存できませんでした。")
        }
    }

    private func restoreBookmarkedFolder() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.folderBookmark) else {
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                saveBookmark(for: url)
            }

            useFolder(url)
            if canStart {
                start()
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.folderBookmark)
            showError("前回選択したフォルダにアクセスできませんでした。再度フォルダを選択してください。")
        }
    }

    private func stopAccessingCurrentFolder() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func showError(_ message: String) {
        errorMessage = message
        showsError = true
    }
}

private enum UserDefaultsKey {
    static let folderBookmark = "folderBookmark"
    static let intervalSeconds = "intervalSeconds"
    static let displayMode = "displayMode"
    static let showsDetectionRegionOverlay = "showsDetectionRegionOverlay"
}

enum ImageDisplayMode: String, CaseIterable, Identifiable {
    case fit
    case fill
    case face

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fit:
            return "全体"
        case .fill:
            return "ウィンド"
        case .face:
            return "顔検出"
        }
    }
}

private struct FocusDetectionResult {
    let point: CGPoint
    let regions: [DetectionRegion]
}

private struct DetectionCandidate {
    let boundingBox: CGRect
    let detectorName: String
    let detectorConfidence: VNConfidence?
    var participatesInFocus = true
}

private struct CharacterClassification {
    let humanConfidence: VNConfidence?
    let nonHumanConfidence: VNConfidence
    let usesHumanFocus: Bool
    let rejectionReason: String?
}

private struct DetectedFocus {
    let point: CGPoint
    let regions: [DetectionRegion]

    init(
        candidates: [DetectionCandidate],
        classifications: [CharacterClassification?]
    ) {
        regions = zip(candidates, classifications).map { candidate, classification in
            let boundingBox = candidate.boundingBox
            let rect = CGRect(
                x: boundingBox.minX,
                y: 1 - boundingBox.maxY,
                width: boundingBox.width,
                height: boundingBox.height
            )

            return DetectionRegion(
                rect: rect,
                detectorName: candidate.detectorName,
                detectorConfidence: candidate.detectorConfidence,
                humanConfidence: classification?.humanConfidence,
                nonHumanConfidence: classification?.nonHumanConfidence,
                usesHumanFocus: classification?.usesHumanFocus ?? false,
                participatesInFocus: candidate.participatesInFocus,
                rejectionReason: classification?.rejectionReason
            )
        }

        let focusableRegions = regions.filter(\.participatesInFocus)
        let prioritizedRegions = focusableRegions.filter(\.usesHumanFocus).map(\.rect)
        let fallbackRegions = focusableRegions
            .filter { $0.rejectionReason != "non_human" }
            .map(\.rect)
        let allRegionRects = focusableRegions.map(\.rect)
        let focusRegions = prioritizedRegions.isEmpty
            ? (fallbackRegions.isEmpty ? allRegionRects : fallbackRegions)
            : prioritizedRegions
        guard let firstRegion = focusRegions.first else {
            point = CGPoint(x: 0.5, y: 0.5)
            return
        }

        let combinedRegion = focusRegions.dropFirst().reduce(firstRegion) { partialResult, region in
            partialResult.union(region)
        }
        point = CGPoint(x: combinedRegion.midX, y: combinedRegion.midY)
    }
}
