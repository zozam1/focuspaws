//
//  ActivityTimerView.swift
//  table
//

import SwiftUI

struct ActivityTimerView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var recordService: ActivityRecordService
    @EnvironmentObject var rewardService: DailyRewardService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedActivity: ActivityType?
    @State private var isRunning = false
    @State private var isPaused = false
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var startTime: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if let user = authService.currentUser {
                    CharacterImageView(
                        animal: user.animal,
                        activity: visibleActivity,
                        animated: true
                    )
                    .frame(width: 240, height: 240)
                    .padding(.bottom, 16)
                }

                Text(timeString)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(isPaused ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.2), value: elapsedSeconds)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.bottom, 8)

                if isPaused {
                    if let selectedActivity {
                        HStack(spacing: 6) {
                            Image(systemName: ActivityType.resting.sfSymbol)
                            Text("timer.paused \(Text(LocalizedStringKey(selectedActivity.displayKey)))")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 32)
                    }
                } else if let activity = selectedActivity {
                    HStack(spacing: 6) {
                        Image(systemName: activity.sfSymbol)
                        Text(LocalizedStringKey(activity.displayKey))
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color(hex: activity.color) ?? .blue)
                    .padding(.bottom, 32)
                } else {
                    Text("timer.select")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 32)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ActivityType.allCases, id: \.self) { activity in
                            ActivityChip(
                                activity: activity,
                                isSelected: selectedActivity == activity
                            ) {
                                if !isRunning {
                                    selectedActivity = activity
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)

                HStack(spacing: 18) {
                    Button {
                        isRunning ? stopTimer() : startTimer()
                    } label: {
                        Text(isRunning ? "timer.stop" : "timer.start")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: isRunning ? 104 : 120, height: isRunning ? 104 : 120)
                            .background(isRunning ? Color.red.opacity(0.15) : Color.tableInk)
                            .foregroundStyle(isRunning ? .red : Color.tableInverseInk)
                            .clipShape(Circle())
                    }
                    .disabled(selectedActivity == nil && !isRunning)

                    if isRunning {
                        Button {
                            isPaused ? resumeTimer() : pauseTimer()
                        } label: {
                            Text(isPaused ? "timer.resume" : "timer.pause")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 104, height: 104)
                                .background((Color(hex: ActivityType.resting.color) ?? .gray).opacity(0.15))
                                .foregroundStyle(Color(hex: ActivityType.resting.color) ?? .gray)
                                .clipShape(Circle())
                        }
                    }
                }

                Spacer()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await restoreTimerIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, isRunning, !isPaused else { return }
                if let activity = authService.currentUser?.currentActivity,
                   activity.type != .resting {
                    elapsedSeconds = max(0, Int(Date().timeIntervalSince(activity.startedAt)))
                    startTime = activity.startedAt
                }
                startTicking()
            }
            .onChange(of: authService.currentUser?.currentActivity?.startedAt) { _, newStartedAt in
                guard isRunning, !isPaused, let newStartedAt else { return }
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(newStartedAt)))
                startTime = newStartedAt
            }
        }
    }

    private func restoreTimerIfNeeded() async {
        guard !isRunning,
              let activity = authService.currentUser?.currentActivity,
              activity.type != .resting
        else { return }
        selectedActivity = activity.type
        startTime = activity.startedAt
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(activity.startedAt)))
        isRunning = true
        isPaused = false
        startTicking()
        LiveActivityManager.shared.restore()
    }

    private var visibleActivity: ActivityType? {
        isPaused ? .resting : selectedActivity
    }

    var timeString: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func startTimer() {
        guard let activity = selectedActivity else { return }
        isRunning = true
        isPaused = false
        startTime = Date()
        elapsedSeconds = 0
        publishActivity(activity)
        startTicking()
        LiveActivityManager.shared.start(
            activityType: activity,
            nickname: authService.currentUser?.nickname ?? "",
            startedAt: Date()
        )
    }

    private func pauseTimer() {
        guard isRunning, !isPaused else { return }
        timer?.invalidate()
        timer = nil
        isPaused = true
        saveSegmentBeforePause()
        Task {
            await authService.updateActivity(ActivityStatus(type: .resting, startedAt: Date()))
        }
        if let activity = selectedActivity {
            LiveActivityManager.shared.pause(
                activityType: activity,
                nickname: authService.currentUser?.nickname ?? "",
                startedAt: Date()
            )
        }
    }

    private func resumeTimer() {
        guard isRunning, isPaused, let activity = selectedActivity else { return }
        isPaused = false
        startTime = Date()
        publishActivity(activity)
        startTicking()
        LiveActivityManager.shared.resume(
            activityType: activity,
            nickname: authService.currentUser?.nickname ?? "",
            startedAt: Date()
        )
    }

    /// 일시정지 전까지 쌓인 세그먼트 저장 (10초 미만은 버림)
    private func saveSegmentBeforePause() {
        guard let activity = selectedActivity, activity != .resting, let start = startTime else { return }
        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(start)))
        startTime = nil
        guard duration >= 10 else { return }
        let record = ActivityRecord(
            id: UUID().uuidString,
            userId: authService.currentUser?.id ?? "",
            type: activity,
            startedAt: start,
            endedAt: now,
            duration: duration
        )
        Task {
            try? await recordService.saveRecord(record)
            await checkMilestones()
        }
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
            if elapsedSeconds % 60 == 0 {
                autoSaveSegment()
            }
        }
    }

    private func autoSaveSegment() {
        guard let activity = selectedActivity, activity != .resting, let start = startTime else { return }
        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(start)))
        guard duration >= 10 else { return }
        let record = ActivityRecord(
            id: UUID().uuidString,
            userId: authService.currentUser?.id ?? "",
            type: activity,
            startedAt: start,
            endedAt: now,
            duration: duration
        )
        startTime = now
        Task {
            try? await recordService.saveRecord(record)
            await checkMilestones()
        }
    }

    private func checkMilestones() async {
        guard let uid = authService.currentUser?.id else { return }
        let todaySeconds = recordService.activeDuration(for: Date())
        await rewardService.checkMilestones(todayActiveSeconds: todaySeconds, userId: uid)
        await authService.fetchCurrentUser()
    }

    private func publishActivity(_ activity: ActivityType) {
        let activeStartedAt = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
        let status = ActivityStatus(type: activity, startedAt: activeStartedAt)
        Task { await authService.updateActivity(status, notifyFriends: true) }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        LiveActivityManager.shared.stop()

        defer {
            elapsedSeconds = 0
            startTime = nil
        }

        guard let activity = selectedActivity, activity != .resting, let start = startTime else {
            Task { await authService.updateActivity(nil) }
            return
        }
        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(start)))
        guard duration >= 10 else {
            Task { await authService.updateActivity(nil) }
            return
        }

        let record = ActivityRecord(
            id: UUID().uuidString,
            userId: authService.currentUser?.id ?? "",
            type: activity,
            startedAt: start,
            endedAt: now,
            duration: duration
        )

        Task {
            await authService.updateActivity(nil)
            try? await recordService.saveRecord(record)
            await checkMilestones()
        }
    }
}

struct ActivityChip: View {
    let activity: ActivityType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: activity.sfSymbol)
                Text(LocalizedStringKey(activity.displayKey))
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color(hex: activity.color)?.opacity(0.15) ?? Color.systemGray5 : Color.systemGray6)
            .foregroundStyle(isSelected ? Color(hex: activity.color) ?? .primary : .primary)
            .cornerRadius(20)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(hex: activity.color) ?? .clear : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
