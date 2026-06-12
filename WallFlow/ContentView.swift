import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ImageSlideshowViewModel
    @State private var showsControls = true
    @State private var hideControlsTask: DispatchWorkItem?

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

            if let image = viewModel.currentImage {
                displayedImage(
                    image,
                    focusPoint: viewModel.currentFocusPoint,
                    detectionRegions: viewModel.currentDetectionRegions
                )
            } else {
                placeholder
            }

            topRightStatusOverlay
        }
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
    private func displayedImage(
        _ image: CGImage,
        focusPoint: CGPoint,
        detectionRegions: [DetectionRegion]
    ) -> some View {
        switch viewModel.displayMode {
        case .fit:
            FocalImageView(
                image: image,
                focusPoint: CGPoint(x: 0.5, y: 0.5),
                detectionRegions: viewModel.showsDetectionRegionOverlay ? detectionRegions : [],
                scalingMode: .fit
            )
                .padding(12)
        case .fill:
            FocalImageView(
                image: image,
                focusPoint: CGPoint(x: 0.5, y: 0.5),
                detectionRegions: viewModel.showsDetectionRegionOverlay ? detectionRegions : [],
                scalingMode: .fill
            )
        case .face:
            FocalImageView(
                image: image,
                focusPoint: focusPoint,
                detectionRegions: viewModel.showsDetectionRegionOverlay ? detectionRegions : [],
                scalingMode: .fill
            )
        }
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
