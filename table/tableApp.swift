//
//  tableApp.swift
//  table
//
//  Created by hyemin cho on 5/16/26.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import UIKit
import WidgetKit

@main
struct tableApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationAppDelegate.self) private var pushNotificationDelegate
    @StateObject private var authService = AuthService()
    @StateObject private var roomService = RoomService()
    @StateObject private var recordService = ActivityRecordService()
    @StateObject private var rewardService = DailyRewardService()
    @StateObject private var broadcastService = BroadcastService()
    @StateObject private var purchaseService = PurchaseService()
    @AppStorage(AppLanguageStorage.key) private var appLanguageRaw = AppLanguage.system.rawValue

    init() {
        FirebaseApp.configure()
        PushNotificationService.shared.configure()
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(appLanguageRaw)
                .environment(\.locale, Locale(identifier: selectedLanguage.localeIdentifier))
                .preferredColorScheme(.light)
                .environmentObject(authService)
                .environmentObject(roomService)
                .environmentObject(recordService)
                .environmentObject(rewardService)
                .environmentObject(broadcastService)
                .environmentObject(purchaseService)
                .task(id: "\(authService.currentUser?.id ?? "")-\(appLanguageRaw)") {
                    guard authService.currentUser?.id != nil else { return }
                    await PushNotificationService.shared.ensureDefaultSettingsForCurrentUser()
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    guard url.scheme == "table",
                          url.host == "room",
                          let roomId = url.pathComponents.dropFirst().first
                    else { return }
                    roomService.deepLinkRoomId = roomId
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        authService.saveMyWidgetData()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    if phase == .background {
                        authService.saveMyWidgetData()
                        WidgetCenter.shared.reloadAllTimelines()
                        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "autoSave") {}
                        Task {
                            await autoSaveActivity()
                            UIApplication.shared.endBackgroundTask(bgTask)
                        }
                    }
                }
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private func autoSaveActivity() async {
        guard let user = authService.currentUser,
              let activity = user.currentActivity,
              activity.type != .resting
        else { return }

        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(activity.startedAt)))
        guard duration >= 60 else { return } // 1분 미만은 저장 안 함

        let record = ActivityRecord(
            id: UUID().uuidString,
            userId: user.id,
            type: activity.type,
            startedAt: activity.startedAt,
            endedAt: now,
            duration: duration
        )
        try? await recordService.saveRecord(record)

        let todaySeconds = recordService.activeDuration(for: Date())
        await rewardService.checkMilestones(todayActiveSeconds: todaySeconds, userId: user.id)

        // 다음 자동저장과 중복 방지: 세그먼트 시작 시간을 now로 갱신
        await authService.updateActivity(ActivityStatus(type: activity.type, startedAt: now))
    }
}
