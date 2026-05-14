import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ImageSlideshowViewModel
    @State private var showsControls = true
    @State private var hideControlsTask: DispatchWorkItem?
    @State private var displayedSlides: [DisplayedSlide] = []
    @State private var visibleSlideID: Int?
    @State private var slideCleanupTask: DispatchWorkItem?

    private let imageTransitionDuration = 0.8

    var body: some View {
        ZStack(alignment: .bottom) {
            imageArea

            if showsControls {
                controls
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
        .background(WindowConfigurator())
        .onHover { hovering in
            if hovering {
                revealControls()
            } else if viewModel.isRunning {
                hideControlsSoon(after: 0.6)
            }
        }
        .onTapGesture {
            revealControls()
        }
        .onAppear {
            updateDisplayedSlides(animated: false)
            if viewModel.isRunning {
                hideControlsSoon()
            }
        }
        .onChange(of: viewModel.isRunning) { _, isRunning in
            if isRunning {
                hideControlsSoon()
            } else {
                hideControlsTask?.cancel()
                showsControls = true
            }
        }
        .onChange(of: viewModel.currentImageRevision) { _, _ in
            updateDisplayedSlides(animated: true)
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
        .alert("画像を読み込めません", isPresented: $viewModel.showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            Color.black

            if displayedSlides.isEmpty {
                placeholder
            } else {
                ZStack {
                    ForEach(displayedSlides) { slide in
                        displayedImage(slide)
                            .opacity(slide.id == visibleSlideID ? 1 : 0)
                    }
                }
            }

            topRightStatusOverlay
        }
        .animation(.easeInOut(duration: imageTransitionDuration), value: visibleSlideID)
        .clipped()
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(viewModel.placeholderText)
                .foregroundStyle(.secondary)
        }
    }

    private var topRightStatusOverlay: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(timeline.date, format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("フォルダ選択") {
                viewModel.selectFolder()
                revealControls()
            }

            Text(viewModel.folderDisplayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("表示", selection: $viewModel.displayMode) {
                ForEach(ImageDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Toggle("枠", isOn: $viewModel.showsDetectionRegionOverlay)
                .toggleStyle(.switch)
                .disabled(viewModel.displayMode != .face)

            Button {
                viewModel.showPreviousImage()
                revealControls()
            } label: {
                Label("前へ", systemImage: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!viewModel.canGoPrevious)

            Button {
                viewModel.showNextImage()
                revealControls()
            } label: {
                Label("次へ", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!viewModel.canGoNext)

            Text("間隔")

            TextField("秒", value: $viewModel.intervalSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit {
                    viewModel.normalizeInterval()
                    revealControls()
                }

            Text("秒")

            Button(viewModel.isRunning ? "停止" : "開始") {
                viewModel.toggleRunning()
                revealControls()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewModel.canStart)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .shadow(radius: 12, y: 4)
        .onHover { hovering in
            if hovering {
                hideControlsTask?.cancel()
            } else if viewModel.isRunning {
                hideControlsSoon()
            }
        }
    }

    @ViewBuilder
    private func displayedImage(_ slide: DisplayedSlide) -> some View {
        switch viewModel.displayMode {
        case .fit:
            Image(nsImage: slide.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        case .fill:
            FocalImageView(image: slide.image, focusPoint: CGPoint(x: 0.5, y: 0.5))
        case .face:
            FocalImageView(
                image: slide.image,
                focusPoint: slide.focusPoint,
                detectionRegion: viewModel.showsDetectionRegionOverlay ? slide.detectionRegion : nil
            )
        }
    }

    private func updateDisplayedSlides(animated: Bool) {
        slideCleanupTask?.cancel()

        guard let image = viewModel.currentImage else {
            displayedSlides = []
            visibleSlideID = nil
            return
        }

        let slide = DisplayedSlide(
            id: viewModel.currentImageRevision,
            image: image,
            focusPoint: viewModel.currentFocusPoint,
            detectionRegion: viewModel.currentDetectionRegion
        )

        if displayedSlides.last?.id == slide.id {
            displayedSlides[displayedSlides.count - 1] = slide
            visibleSlideID = slide.id
            return
        }

        if animated {
            displayedSlides.append(slide)
            displayedSlides = Array(displayedSlides.suffix(2))
            DispatchQueue.main.async {
                visibleSlideID = slide.id
            }
        } else {
            displayedSlides = [slide]
            visibleSlideID = slide.id
        }

        let task = DispatchWorkItem {
            displayedSlides = displayedSlides.filter { $0.id == visibleSlideID }
        }
        slideCleanupTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + imageTransitionDuration + 0.1, execute: task)
    }

    private func revealControls() {
        hideControlsTask?.cancel()
        showsControls = true

        if viewModel.isRunning {
            hideControlsSoon()
        }
    }

    private func hideControlsSoon(after delay: TimeInterval = 2.5) {
        hideControlsTask?.cancel()

        let task = DispatchWorkItem {
            showsControls = false
        }
        hideControlsTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
}

private struct DisplayedSlide: Identifiable {
    let id: Int
    let image: NSImage
    let focusPoint: CGPoint
    let detectionRegion: CGRect?
}
