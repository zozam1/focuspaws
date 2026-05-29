//
//  AuthService.swift
//  table
//

import Foundation
import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import Security
import UIKit
import WidgetKit

class AuthService: ObservableObject {
    @Published var currentUser: UserModel?
    @Published var isLoggedIn = false
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser {
                    await self?.fetchUser(uid: firebaseUser.uid)
                    self?.isLoggedIn = true
                } else {
                    self?.currentUser = nil
                    self?.isLoggedIn = false
                }
                self?.isLoading = false
            }
        }
    }

    deinit {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    func signUp(email: String, password: String, nickname: String, animal: UserModel.AnimalType) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let uid = result.user.uid
        let user = UserModel(
            id: uid,
            nickname: nickname,
            animal: animal,
            currentActivity: nil,
            createdAt: Date(),
            coins: CurrencyConfig.startingBalance
        )
        try await saveUser(user)
        try await createInitialRoom(for: user)
        await MainActor.run { self.currentUser = user }
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    @MainActor
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthProviderError.missingGoogleClientID
        }
        guard let presentingViewController = Self.presentingViewController() else {
            throw AuthProviderError.missingPresentingViewController
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        let googleUser = signInResult.user

        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthProviderError.missingGoogleIdentityToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        let nickname = googleUser.profile?.name ?? authResult.user.displayName
        try await ensureUserProfile(uid: authResult.user.uid, nicknameFallback: nickname)
    }

    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 7.0, *)
    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 7.0, *)
    func signInWithApple(credential appleIDCredential: ASAuthorizationAppleIDCredential) async throws {
        defer { currentAppleNonce = nil }
        guard let nonce = currentAppleNonce else {
            throw AuthProviderError.missingNonce
        }
        guard let tokenData = appleIDCredential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthProviderError.missingIdentityToken
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        let nickname = Self.displayName(from: appleIDCredential.fullName)
            ?? result.user.displayName
            ?? NSLocalizedString("focuspaws.friend", comment: "")
        try await ensureUserProfile(uid: result.user.uid, nicknameFallback: nickname)
    }

    func signOut() throws {
        currentUser = nil
        isLoggedIn = false
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    private func fetchUser(uid: String) async {
        do {
            try await ensureUserProfile(
                uid: uid,
                nicknameFallback: Auth.auth().currentUser?.displayName
            )
        } catch {
            print("유저 불러오기 실패: \(error)")
        }
    }

    private func saveUser(_ user: UserModel) async throws {
        let data = try Firestore.Encoder().encode(user)
        try await db.collection("users").document(user.id).setData(data)
    }

    private func ensureUserProfile(uid: String, nicknameFallback: String? = nil) async throws {
        let doc = try await db.collection("users").document(uid).getDocument()
        if let data = doc.data() {
            let user = try Firestore.Decoder().decode(UserModel.self, from: data)
            await MainActor.run {
                self.currentUser = user
                self.saveMyWidgetData()
            }
            return
        }

        let nickname = Self.normalizedNickname(nicknameFallback)
        let user = UserModel(
            id: uid,
            nickname: nickname,
            animal: .cat,
            currentActivity: nil,
            createdAt: Date(),
            coins: CurrencyConfig.startingBalance
        )
        try await saveUser(user)
        try await createInitialRoom(for: user, roomId: "\(uid)_home")
        await MainActor.run {
            self.currentUser = user
            self.saveMyWidgetData()
        }
    }

    private func createInitialRoom(for user: UserModel, roomId: String = UUID().uuidString) async throws {
        let roomRef = db.collection("rooms").document(roomId)
        let existing = try await roomRef.getDocument()
        guard !existing.exists else { return }

        let room = RoomModel(
            id: roomId,
            name: String(format: NSLocalizedString("room.default_name %@", comment: ""), user.nickname),
            inviteCode: RoomModel.generateInviteCode(),
            createdBy: user.id,
            memberIds: [user.id],
            createdAt: Date()
        )
        let roomData = try Firestore.Encoder().encode(room)
        try await roomRef.setData(roomData)
    }

    func fetchCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await fetchUser(uid: uid)
    }

    func updateAnimal(_ animal: UserModel.AnimalType) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData(["animal": animal.rawValue])
            await MainActor.run {
                self.currentUser?.animal = animal
                self.saveMyWidgetData()
            }
        } catch {
            print("캐릭터 업데이트 실패: \(error)")
        }
    }

    func updateNickname(_ nickname: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).updateData(["nickname": nickname])
        await MainActor.run { self.currentUser?.nickname = nickname }
    }

    func updateStatusMessage(_ message: String?) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            if let message, !message.isEmpty {
                try await db.collection("users").document(uid).updateData(["statusMessage": message])
            } else {
                try await db.collection("users").document(uid).updateData(["statusMessage": FieldValue.delete()])
            }
            await MainActor.run { self.currentUser?.statusMessage = message }
        } catch {
            print("상태메시지 업데이트 실패: \(error)")
        }
    }

    func updateActivity(_ activity: ActivityStatus?, notifyFriends: Bool = false) async {
        // 위젯은 네트워크 결과와 무관하게 즉시 업데이트
        await MainActor.run {
            self.currentUser?.currentActivity = activity
            self.saveMyWidgetData()
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            if let activity {
                let data = try Firestore.Encoder().encode(activity)
                try await db.collection("users").document(uid).updateData(["currentActivity": data])
                if notifyFriends, activity.type != .resting {
                    await createActivityStartNotifications(activity: activity, fromUserId: uid)
                }
            } else {
                try await db.collection("users").document(uid).updateData(["currentActivity": FieldValue.delete()])
            }
        } catch {
            print("활동 업데이트 실패: \(error)")
        }
    }

    private func createActivityStartNotifications(activity: ActivityStatus, fromUserId: String) async {
        do {
            let snapshot = try await db.collection("rooms")
                .whereField("memberIds", arrayContains: fromUserId)
                .getDocuments()

            var targetUserIds = Set<String>()
            var roomIdByTargetUserId: [String: String] = [:]
            for document in snapshot.documents {
                let roomId = document.documentID
                let memberIds = document.data()["memberIds"] as? [String] ?? []
                for memberId in memberIds where memberId != fromUserId {
                    targetUserIds.insert(memberId)
                    roomIdByTargetUserId[memberId] = roomId
                }
            }

            guard !targetUserIds.isEmpty else { return }

            let fromNickname = currentUser?.nickname ?? NSLocalizedString("cheer.someone", comment: "")
            let activityName = NSLocalizedString(activity.type.displayKey, comment: "")
            let title = NSLocalizedString("notification.activity_started.title", comment: "")
            let body = String(
                format: NSLocalizedString("notification.activity_started.body %@ %@", comment: ""),
                fromNickname,
                activityName
            )

            let batch = db.batch()
            for targetUserId in targetUserIds {
                let notificationRef = db.collection("users")
                    .document(targetUserId)
                    .collection("notifications")
                    .document()

                batch.setData([
                    "type": "friendActivityStarted",
                    "preferenceKey": PushNotificationPreferenceKey.friendActivityStarted,
                    "fromUserId": fromUserId,
                    "fromNickname": fromNickname,
                    "roomId": roomIdByTargetUserId[targetUserId] ?? "",
                    "activityType": activity.type.rawValue,
                    "activityName": activityName,
                    "title": title,
                    "body": body,
                    "isRead": false,
                    "createdAt": Timestamp(date: Date())
                ], forDocument: notificationRef)
            }

            try await batch.commit()
        } catch {
            print("친구 활동 시작 알림 생성 실패: \(error)")
        }
    }

    // MARK: - 출석 체크
    func checkIn(todayActiveSeconds: Int) async throws {
        guard todayActiveSeconds >= CheckInConfig.requiredActiveSeconds else {
            throw CheckInError.notEnoughActiveTime(currentSeconds: todayActiveSeconds)
        }
        guard let uid = Auth.auth().currentUser?.uid,
              let user = currentUser
        else {
            throw CheckInError.notLoggedIn
        }
        guard user.canCheckInToday else {
            throw CheckInError.alreadyCompleted
        }

        let newCoins = user.coins + CheckInConfig.rewardAmount
        try await db.collection("users").document(uid).updateData([
            "coins": newCoins,
            "lastCheckIn": Timestamp(date: Date())
        ])
        await MainActor.run {
            self.currentUser?.coins = newCoins
            self.currentUser?.lastCheckIn = Date()
        }
    }

    // MARK: - 계정 삭제
    func deleteAccount() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Firestore 유저 데이터 삭제
        try await db.collection("users").document(uid).delete()

        // 방에서 나가기 (멤버로 있는 방)
        let roomsAsOwner = try await db.collection("rooms")
            .whereField("createdBy", isEqualTo: uid)
            .getDocuments()
        for doc in roomsAsOwner.documents {
            try await doc.reference.delete()
        }
        let roomsAsMember = try await db.collection("rooms")
            .whereField("memberIds", arrayContains: uid)
            .getDocuments()
        for doc in roomsAsMember.documents {
            try await doc.reference.updateData([
                "memberIds": FieldValue.arrayRemove([uid])
            ])
        }

        // Firebase Auth 계정 삭제
        try await Auth.auth().currentUser?.delete()
    }

    // MARK: - 재화 충전
    func rechargeCurrency(_ amount: Int) async throws {
        guard amount > 0, let uid = Auth.auth().currentUser?.uid, let user = currentUser else { return }
        let newCoins = user.coins + amount
        try await db.collection("users").document(uid).updateData(["coins": newCoins])
        await MainActor.run { self.currentUser?.coins = newCoins }
    }

    // MARK: - 동물 구매
    func purchaseAnimal(_ animal: UserModel.AnimalType) async throws {
        guard let uid = Auth.auth().currentUser?.uid, let user = currentUser else { return }
        guard !user.ownsAnimal(animal) else { return }
        guard CurrencyConfig.isUnlimitedForNow || user.coins >= animal.price else { throw ShopError.notEnoughCoins }
        let newCoins = CurrencyConfig.isUnlimitedForNow ? user.coins : user.coins - animal.price
        var newOwned = user.ownedAnimalIds
        newOwned.append(animal.rawValue)
        try await db.collection("users").document(uid).updateData([
            "coins": newCoins,
            "ownedAnimalIds": newOwned
        ])
        await MainActor.run {
            self.currentUser?.coins = newCoins
            self.currentUser?.ownedAnimalIds = newOwned
        }
    }

    // MARK: - 스킨 구매
    func purchaseSkin(_ skinId: String, price: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid, let user = currentUser else { return }
        guard !user.ownsSkin(skinId) else { return }
        guard CurrencyConfig.isUnlimitedForNow || user.coins >= price else { throw ShopError.notEnoughCoins }
        let newCoins = CurrencyConfig.isUnlimitedForNow ? user.coins : user.coins - price
        var newOwned = user.ownedSkinIds
        newOwned.append(skinId)
        try await db.collection("users").document(uid).updateData([
            "coins": newCoins,
            "ownedSkinIds": newOwned
        ])
        await MainActor.run {
            self.currentUser?.coins = newCoins
            self.currentUser?.ownedSkinIds = newOwned
        }
    }

    // MARK: - 방 스킨 구매
    func purchaseRoomSkin(_ skinId: String, price: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid, let user = currentUser else { return }
        guard !user.ownsRoomSkin(skinId) else { return }
        guard CurrencyConfig.isUnlimitedForNow || user.coins >= price else { throw ShopError.notEnoughCoins }
        let newCoins = CurrencyConfig.isUnlimitedForNow ? user.coins : user.coins - price
        var newOwned = user.ownedRoomSkinIds
        newOwned.append(skinId)
        try await db.collection("users").document(uid).updateData([
            "coins": newCoins,
            "ownedRoomSkinIds": newOwned
        ])
        await MainActor.run {
            self.currentUser?.coins = newCoins
            self.currentUser?.ownedRoomSkinIds = newOwned
        }
    }

    func saveMyWidgetData() {
        guard let user = currentUser else { return }
        let data = WidgetMyData(
            nickname: user.nickname,
            animalType: user.animal.rawValue,
            activityName: user.currentActivity?.type.displayKey,  // localization key
            activityColor: user.currentActivity?.type.color,
            activitySymbol: user.currentActivity?.type.sfSymbol,
            startedAt: user.currentActivity?.startedAt
        )
        SharedWidgetData.saveMyData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func normalizedNickname(_ value: String?) -> String {
        let fallback = NSLocalizedString("focuspaws.friend", comment: "")
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(12))
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(result == errSecSuccess, "Unable to generate nonce")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func presentingViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }
        return topViewController(from: root)
    }

    @MainActor
    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }
}

// MARK: - 상점 에러
enum ShopError: LocalizedError {
    case notEnoughCoins

    var errorDescription: String? {
        switch self {
        case .notEnoughCoins: return NSLocalizedString("shop.error.funds", comment: "")
        }
    }
}

enum CheckInError: LocalizedError {
    case notLoggedIn
    case alreadyCompleted
    case notEnoughActiveTime(currentSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return NSLocalizedString("checkin.error.not_logged_in", comment: "")
        case .alreadyCompleted:
            return NSLocalizedString("checkin.error.already", comment: "")
        case .notEnoughActiveTime(let currentSeconds):
            let remaining = max(0, CheckInConfig.requiredActiveSeconds - currentSeconds)
            let minutes = max(1, Int(ceil(Double(remaining) / 60.0)))
            return String(format: NSLocalizedString("checkin.error.remaining %lld", comment: ""), minutes)
        }
    }
}

enum AuthProviderError: LocalizedError {
    case missingNonce
    case missingIdentityToken
    case missingGoogleClientID
    case missingGoogleIdentityToken
    case missingPresentingViewController

    var errorDescription: String? {
        switch self {
        case .missingNonce:
            return NSLocalizedString("auth.error.apple.nonce", comment: "")
        case .missingIdentityToken:
            return NSLocalizedString("auth.error.apple.identity", comment: "")
        case .missingGoogleClientID:
            return NSLocalizedString("auth.error.google.client_id", comment: "")
        case .missingGoogleIdentityToken:
            return NSLocalizedString("auth.error.google.identity", comment: "")
        case .missingPresentingViewController:
            return NSLocalizedString("auth.error.presenting", comment: "")
        }
    }
}
