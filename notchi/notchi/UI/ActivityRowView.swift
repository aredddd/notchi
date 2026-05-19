import Combine
import SwiftUI

struct ActivityRowView: View {
    let event: SessionEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                bullet
                toolName
                if event.status != .running {
                    statusLabel
                }
            }

            if let description = event.description {
                Text(description)
                    .font(.system(size: 12).italic())
                    .foregroundColor(TerminalColors.dimmedText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 13)
            }
        }
        .padding(.vertical, 4)
    }

    private var bullet: some View {
        Circle()
            .fill(bulletColor)
            .frame(width: 5, height: 5)
    }

    private var bulletColor: Color {
        switch event.status {
        case .running: return TerminalColors.amber
        case .success: return TerminalColors.green
        case .error: return TerminalColors.red
        }
    }

    private var toolName: some View {
        Text(event.tool ?? event.type)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(TerminalColors.primaryText)
    }

    private var statusLabel: some View {
        let isSuccess = event.status == .success
        return Text(isSuccess ? "Completed" : "Failed")
            .font(.system(size: 12))
            .foregroundColor(isSuccess ? TerminalColors.green : TerminalColors.red)
    }
}

struct QuestionPromptView: View {
    let questions: [PendingQuestion]
    let onSubmitAnswers: (([Int: Int]) -> Bool)?
    @State private var currentIndex = 0
    @State private var selectedOptionIndexesByQuestion: [Int: Int] = [:]
    @State private var hoveredOptionIndex: Int?
    @State private var pressedOptionIndex: Int?
    @State private var isSubmitting = false

    init(
        questions: [PendingQuestion],
        onSubmitAnswers: (([Int: Int]) -> Bool)? = nil
    ) {
        self.questions = questions
        self.onSubmitAnswers = onSubmitAnswers
    }

    private var clampedIndex: Int {
        min(currentIndex, questions.count - 1)
    }

    private var current: PendingQuestion {
        questions[clampedIndex]
    }

    private var hasMultipleQuestions: Bool {
        questions.count > 1
    }

    private var currentHasClickableOptions: Bool {
        current.options.contains { !PendingQuestion.isFreeTextOptionLabel($0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            questionHeader
                .padding(.bottom, 5)
            questionText
                .padding(.bottom, 6)
            optionsList
            if onSubmitAnswers != nil, !currentHasClickableOptions {
                terminalRequiredHint
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TerminalColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TerminalColors.claudeOrange.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .onChange(of: questions.map(\.question)) {
            resetAnswerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchiQuestionOptionShortcut)) { notification in
            guard let optionNumber = notification.object as? Int else { return }
            selectOption(index: optionNumber - 1)
        }
    }

    private var questionHeader: some View {
        HStack {
            if let header = current.header {
                Text(header)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(TerminalColors.claudeOrange)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            if hasMultipleQuestions {
                Text("(\(clampedIndex + 1)/\(questions.count))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(TerminalColors.secondaryText)
            }

            Spacer()

            if hasMultipleQuestions {
                paginationControls
            }
        }
    }

    private var paginationControls: some View {
        HStack(spacing: 2) {
            Button(action: { showQuestion(at: currentIndex - 1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? TerminalColors.primaryText : TerminalColors.dimmedText)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || currentIndex == 0)

            Button(action: { showQuestion(at: currentIndex + 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(currentIndex < questions.count - 1 ? TerminalColors.primaryText : TerminalColors.dimmedText)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || currentIndex == questions.count - 1)
        }
    }

    private var questionText: some View {
        Text(current.question)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(TerminalColors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(current.options.enumerated()), id: \.offset) { index, option in
                let isInteractive = onSubmitAnswers != nil
                let isFreeTextOption = PendingQuestion.isFreeTextOptionLabel(option.label)

                if isInteractive, !isFreeTextOption {
                    Button {
                        selectOption(index: index)
                    } label: {
                        highlightedOptionRow(
                            index: index,
                            option: option,
                            isSelected: selectedOptionIndexesByQuestion[clampedIndex] == index,
                            isPressed: pressedOptionIndex == index
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .simultaneousGesture(pressGesture(for: index))
                } else if isInteractive {
                    highlightedOptionRow(
                        index: index,
                        option: (
                            label: option.label,
                            description: option.description ?? "Use terminal for custom text"
                        ),
                        isPressed: false
                    )
                } else {
                    optionRow(index: index, option: option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightedOptionRow(
        index: Int,
        option: (label: String, description: String?),
        isSelected: Bool = false,
        isPressed: Bool = false
    ) -> some View {
        let isHovered = hoveredOptionIndex == index
        let style = highlightedOptionStyle(isHovered: isHovered, isSelected: isSelected, isPressed: isPressed)

        return HStack(alignment: .center, spacing: 9) {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(TerminalColors.primaryText.opacity(0.82))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(style.badgeFill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.primaryText)
                if let description = option.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(style.stroke, lineWidth: style.strokeWidth)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: style.shadowColor, radius: style.shadowRadius, y: style.shadowYOffset)
        .brightness(isPressed ? 0.035 : 0)
        .scaleEffect(isPressed ? 0.985 : 1, anchor: .center)
        .onHover { isHovering in
            if isHovering {
                hoveredOptionIndex = index
            } else if hoveredOptionIndex == index {
                hoveredOptionIndex = nil
                pressedOptionIndex = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.72, blendDuration: 0.04), value: isPressed)
    }

    private var terminalRequiredHint: some View {
        Text("Use terminal for this question")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(TerminalColors.dimmedText)
            .italic()
    }

    private func highlightedOptionStyle(isHovered: Bool, isSelected: Bool, isPressed: Bool) -> (
        rowFill: Color,
        badgeFill: Color,
        stroke: Color,
        strokeWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) {
        let rowFillOpacity: Double
        let badgeFillOpacity: Double
        let strokeOpacity: Double
        let strokeWidth: CGFloat
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat

        if isPressed {
            rowFillOpacity = 0.46
            badgeFillOpacity = 1
            strokeOpacity = 0.7
            strokeWidth = 1.25
            shadowOpacity = 0.08
            shadowRadius = 3
            shadowYOffset = 1
        } else if isHovered {
            rowFillOpacity = isSelected ? 0.4 : 0.34
            badgeFillOpacity = 1
            strokeOpacity = isSelected ? 0.58 : 0.46
            strokeWidth = isSelected ? 1.15 : 1
            shadowOpacity = isSelected ? 0.16 : 0.14
            shadowRadius = 5
            shadowYOffset = 2
        } else if isSelected {
            rowFillOpacity = 0.28
            badgeFillOpacity = 1
            strokeOpacity = 0.34
            strokeWidth = 1
            shadowOpacity = 0.06
            shadowRadius = 3
            shadowYOffset = 1
        } else {
            rowFillOpacity = 0.22
            badgeFillOpacity = 0.92
            strokeOpacity = 0.16
            strokeWidth = 1
            shadowOpacity = 0
            shadowRadius = 0
            shadowYOffset = 2
        }

        return (
            rowFill: TerminalColors.claudeOrange.opacity(rowFillOpacity),
            badgeFill: TerminalColors.claudeOrangeDeep.opacity(badgeFillOpacity),
            stroke: TerminalColors.claudeOrange.opacity(strokeOpacity),
            strokeWidth: strokeWidth,
            shadowColor: TerminalColors.claudeOrange.opacity(shadowOpacity),
            shadowRadius: shadowRadius,
            shadowYOffset: shadowYOffset
        )
    }

    private static let pressDragTolerance: CGFloat = 8

    private func pressGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let withinTolerance =
                    abs(value.translation.width) <= Self.pressDragTolerance &&
                    abs(value.translation.height) <= Self.pressDragTolerance

                if !isSubmitting && withinTolerance {
                    pressedOptionIndex = index
                } else if pressedOptionIndex == index {
                    pressedOptionIndex = nil
                }
            }
            .onEnded { _ in
                pressedOptionIndex = nil
            }
    }

    private func selectOption(index optionIndex: Int) {
        guard !isSubmitting,
              let onSubmitAnswers,
              current.options.indices.contains(optionIndex),
              !PendingQuestion.isFreeTextOptionLabel(current.options[optionIndex].label) else {
            return
        }

        selectedOptionIndexesByQuestion[clampedIndex] = optionIndex

        if selectedOptionIndexesByQuestion.count < questions.count {
            HapticService.shared.playNavigationTap()
            if let nextIndex = nextUnansweredQuestionIndex(after: clampedIndex) {
                showQuestion(at: nextIndex)
            }
            return
        }

        isSubmitting = true
        let didSubmit = onSubmitAnswers(selectedOptionIndexesByQuestion)
        if didSubmit {
            HapticService.shared.playNavigationTap()
        } else {
            isSubmitting = false
        }
    }

    private func showQuestion(at index: Int) {
        currentIndex = min(max(0, index), questions.count - 1)
        hoveredOptionIndex = nil
        pressedOptionIndex = nil
    }

    private func nextUnansweredQuestionIndex(after index: Int) -> Int? {
        let count = questions.count
        guard count > 0 else { return nil }

        for offset in 1...count {
            let candidate = (index + offset) % count
            if selectedOptionIndexesByQuestion[candidate] == nil {
                return candidate
            }
        }

        return nil
    }

    private func resetAnswerState() {
        currentIndex = 0
        selectedOptionIndexesByQuestion = [:]
        hoveredOptionIndex = nil
        pressedOptionIndex = nil
        isSubmitting = false
    }

    private func optionRow(
        index: Int,
        option: (label: String, description: String?)
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1).")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(TerminalColors.claudeOrange)
                .frame(width: 16, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.primaryText)
                if let description = option.description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.dimmedText)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct WorkingIndicatorView: View {
    let state: NotchiState
    let workingVerb: String
    let color: Color
    @State private var dotCount = 1
    @State private var symbolPhase = 0

    private let dotsTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    private let symbolTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    private var displaySymbol: String {
        WorkingIndicatorPresentation.symbol(for: state.task, phase: symbolPhase)
    }

    private var displayText: String {
        WorkingIndicatorPresentation.text(for: state.task, workingVerb: workingVerb, dots: dots)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(displaySymbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 14, alignment: .center)
            ShimmeringText(
                text: displayText,
                font: .system(size: 12, weight: .medium).italic(),
                color: color,
                isEnabled: state.task != .waiting
            )
        }
        .padding(.leading, -1)
        .onReceive(dotsTimer) { _ in
            dotCount = (dotCount % 3) + 1
        }
        .onReceive(symbolTimer) { _ in
            guard state.task != .waiting else { return }
            symbolPhase = (symbolPhase + 1) % WorkingIndicatorPresentation.animatedSymbols.count
        }
    }
}

private struct ShimmeringText: View {
    let text: String
    let font: Font
    let color: Color
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    private let duration: TimeInterval = 2.5
    private let pauseBetweenSweepsNanoseconds: UInt64 = 1_000_000_000
    private let frameDelayNanoseconds: UInt64 = 16_000_000

    private var shimmerActive: Bool { isEnabled && !reduceMotion }

    private struct ShimmerStateKey: Hashable {
        let isEnabled: Bool
        let reduceMotion: Bool
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .overlay(alignment: .leading) {
                if shimmerActive {
                    shimmerSweep
                        .mask(
                            Text(text)
                                .font(font)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                }
            }
            .task(id: ShimmerStateKey(isEnabled: isEnabled, reduceMotion: reduceMotion)) {
                isSweeping = false
                guard shimmerActive else { return }
                await runShimmerLoop()
            }
    }

    private func runShimmerLoop() async {
        let sweepDurationNanoseconds = UInt64(duration * 1_000_000_000)

        while !Task.isCancelled {
            isSweeping = false

            // WHY: Yield one frame so the reset to false commits before the
            // animated true flip; otherwise SwiftUI coalesces them and the
            // sweep starts mid-screen.
            do {
                try await Task.sleep(nanoseconds: frameDelayNanoseconds)
            } catch {
                return
            }

            withAnimation(.linear(duration: duration)) {
                isSweeping = true
            }

            do {
                try await Task.sleep(nanoseconds: sweepDurationNanoseconds + pauseBetweenSweepsNanoseconds)
            } catch {
                return
            }
        }
    }

    private var shimmerSweep: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sweepWidth = max(width * 0.7, 64)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.03), location: 0.3),
                    .init(color: Color.white.opacity(0.42), location: 0.5),
                    .init(color: Color.white.opacity(0.03), location: 0.7),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: sweepWidth, height: proxy.size.height)
            .offset(x: isSweeping ? width + sweepWidth : -sweepWidth)
        }
        .allowsHitTesting(false)
    }
}

enum WorkingIndicatorPresentation {
    static let animatedSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    static let waitingSymbol = "✳"

    static func symbol(for task: NotchiTask, phase: Int) -> String {
        if task == .waiting {
            return waitingSymbol
        }
        return animatedSymbols[phase % animatedSymbols.count]
    }

    static func text(for task: NotchiTask, workingVerb: String, dots: String) -> String {
        switch task {
        case .compacting:
            return "Compacting\(dots)"
        case .waiting:
            return "Waiting\(dots)"
        default:
            return "\(workingVerb)\(dots)"
        }
    }
}
