import AppKit
import Combine
import CoreML
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

    @Published private(set) var currentImage: NSImage?
    @Published private(set) var currentImageRevision = 0
    @Published private(set) var currentFocusPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var currentDetectionRegion: CGRect?
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
    private static let animeFaceConfidenceThreshold: VNConfidence = 0.3

    private lazy var animeFaceVisionModel: VNCoreMLModel? = {
        guard let modelURL = animeFaceModelURL() else {
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
        guard let image = NSImage(contentsOf: imageURL) else {
            return false
        }

        currentImage = image
        currentImageRevision += 1
        if let focusResult = detectFocusPoint(in: image) {
            currentFocusPoint = focusResult.point
            currentDetectionRegion = focusResult.region
        } else {
            currentFocusPoint = CGPoint(x: 0.5, y: 0.5)
            currentDetectionRegion = nil
        }
        return true
    }

    private func detectFocusPoint(in image: NSImage) -> FocusDetectionResult? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        if let faceFocus = detectFaceFocus(in: cgImage) {
            return FocusDetectionResult(
                point: faceFocus.point,
                region: faceFocus.region
            )
        }

        if let animeFaceFocus = detectAnimeFaceFocus(in: cgImage) {
            return FocusDetectionResult(
                point: animeFaceFocus.point,
                region: animeFaceFocus.region
            )
        }

        if let saliencyFocus = detectSaliencyFocus(in: cgImage) {
            return FocusDetectionResult(
                point: saliencyFocus.point,
                region: saliencyFocus.region
            )
        }

        return nil
    }

    private func animeFaceModelURL() -> URL? {
        Bundle.main.url(forResource: Self.animeFaceModelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: Self.animeFaceModelName, withExtension: "mlpackage")
    }

    private func detectFaceFocus(in cgImage: CGImage) -> DetectedFocus? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let face = request.results?.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return nil
        }

        return DetectedFocus(boundingBox: face.boundingBox)
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

        let detectedFace = request.results?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .filter { $0.confidence >= Self.animeFaceConfidenceThreshold }
            .max(by: { lhs, rhs in
                lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
            })

        guard let detectedFace else {
            return nil
        }

        return DetectedFocus(boundingBox: detectedFace.boundingBox)
    }

    private func detectSaliencyFocus(in cgImage: CGImage) -> DetectedFocus? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard
            let observation = request.results?.first,
            let object = observation.salientObjects?.max(by: { lhs, rhs in
                lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
            })
        else {
            return nil
        }

        return DetectedFocus(boundingBox: object.boundingBox)
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
    let region: CGRect
}

private struct DetectedFocus {
    let point: CGPoint
    let region: CGRect

    init(boundingBox: CGRect) {
        point = CGPoint(x: boundingBox.midX, y: 1 - boundingBox.midY)
        region = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }
}
