//
//  ProfileView.swift
//  table
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var recordService: ActivityRecordService
    @EnvironmentObject var rewardService: DailyRewardService
    @EnvironmentObject var broadcastService: BroadcastService
    @State private var showProfileEditor = false
    @State private var showShop = false
    @State private var showSettings = false

    var user: UserModel? { authService.currentUser }

    private var todayActiveSeconds: Int {
        recordService.activeDuration(for: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                // 프로필 상단
                Section {
                    Button {
                        showProfileEditor = true
                    } label: {
                        HStack(spacing: 16) {
                            CharacterImageView(
                                animal: user?.animal ?? .cat,
                                activity: nil
                            )
                            .frame(width: 72, height: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user?.nickname ?? "")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text(LocalizedStringKey(user?.animal.displayKey ?? ""))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("profile.edit.hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Image(systemName: CurrencyConfig.symbol)
                                    .foregroundStyle(.purple)
                                    .font(.system(size: 14))
                                Text("\(CurrencyConfig.displayedBalance(for: user?.coins ?? 0))")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                // 오늘의 리워드
                Section {
                    DailyRewardBar(
                        todayActiveSeconds: todayActiveSeconds,
                        state: rewardService.state
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // 상점
                Section {
                    Button {
                        showShop = true
                    } label: {
                        HStack {
                            Label("profile.shop", systemImage: "bag.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: CurrencyConfig.symbol)
                                    .foregroundStyle(.purple)
                                    .font(.system(size: 10))
                                Text("\(CurrencyConfig.displayedBalance(for: user?.coins ?? 0))")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13))
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showShop) {
                ShopView()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorSheet()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(authService)
                    .environmentObject(broadcastService)
            }
        }
    }
}

// MARK: - 환경설정
// 어드민 유저 ID — Firebase Console에서 확인한 내 UID 입력
private let adminUserID = "z2l2d7l3ehS7rtahK6yzTWx5KRy1"

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var broadcastService: BroadcastService
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var showFeedback = false
    @AppStorage(AppLanguageStorage.key) private var appLanguageRaw = AppLanguage.system.rawValue

    private var isAdmin: Bool {
        authService.currentUser?.id == adminUserID
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $appLanguageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    } label: {
                        Label("settings.language", systemImage: "globe")
                    }
                }

                if isAdmin {
                    Section("settings.admin") {
                        NavigationLink {
                            AdminBroadcastView()
                                .environmentObject(broadcastService)
                        } label: {
                            Label("settings.admin.broadcast", systemImage: "megaphone.fill")
                        }
                    }
                }

                // 정책
                Section {
                    Link(destination: URL(string: "https://zozam1.github.io/focuspaws/privacy-policy.html")!) {
                        HStack {
                            Label("settings.privacy", systemImage: "hand.raised.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://zozam1.github.io/focuspaws/terms-of-service.html")!) {
                        HStack {
                            Label("settings.terms", systemImage: "doc.text.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 문의하기
                Section {
                    Button {
                        showFeedback = true
                    } label: {
                        Label("settings.feedback", systemImage: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.primary)
                    }
                }

                // 계정
                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("settings.logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        showDeleteAccountAlert = true
                    } label: {
                        if isDeletingAccount {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("settings.deleting")
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Label("settings.delete.account", systemImage: "trash.fill")
                        }
                    }
                    .disabled(isDeletingAccount)
                }
            }
            .navigationTitle("settings.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView()
                    .environmentObject(authService)
            }
            .alert("settings.logout", isPresented: $showSignOutAlert) {
                Button("common.cancel", role: .cancel) {}
                Button("settings.logout", role: .destructive) {
                    try? authService.signOut()
                }
            } message: {
                Text("settings.logout.confirm")
            }
            .alert("settings.delete.account", isPresented: $showDeleteAccountAlert) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("settings.delete.confirm")
            }
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            try await authService.deleteAccount()
        } catch {
            isDeletingAccount = false
        }
    }
}

// MARK: - 통합 프로필 편집
struct ProfileEditorSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var selectedAnimal: UserModel.AnimalType = .cat
    @State private var isSaving = false
    @State private var errorMessage = ""

    private var ownedAnimals: [UserModel.AnimalType] {
        UserModel.AnimalType.allCases.filter {
            authService.currentUser?.ownsAnimal($0) ?? $0.isFree
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 10) {
                        CharacterImageView(
                            animal: selectedAnimal,
                            activity: nil,
                            animated: true
                        )
                        .frame(width: 118, height: 118)

                        Text(LocalizedStringKey(selectedAnimal.displayKey))
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    sectionTitle("profile.nickname")
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("profile.nickname", text: $nickname)
                            .font(.system(size: 17, weight: .medium))
                            .padding()
                            .background(Color.systemGray6)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onChange(of: nickname) { _, new in
                                nickname = new.truncatedToNicknameWidth()
                            }
                        Text("\(nickname.displayWidth)/\(String.nicknameMaxWidth)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    sectionTitle("profile.character")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(ownedAnimals, id: \.self) { animal in
                            AnimalSelectCard(animal: animal, isSelected: selectedAnimal == animal) {
                                selectedAnimal = animal
                            }
                        }
                    }

                    sectionTitle("profile.outfit")
                    HStack(spacing: 10) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("profile.outfit.soon")
                                .font(.system(size: 14, weight: .semibold))
                            Text("profile.outfit.desc")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tableSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.tableSoftStroke, lineWidth: 1))

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .background(Color.tableGroupedBackground)
            .navigationTitle("profile.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("common.save")
                        }
                    }
                    .disabled(!nickname.trimmingCharacters(in: .whitespaces).isValidNicknameLength || isSaving)
                }
            }
            .onAppear {
                nickname = authService.currentUser?.nickname ?? ""
                selectedAnimal = authService.currentUser?.animal ?? .cat
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
    }

    private func save() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSaving = true
        errorMessage = ""
        do {
            if trimmed != authService.currentUser?.nickname {
                try await authService.updateNickname(trimmed)
            }
            if selectedAnimal != authService.currentUser?.animal {
                await authService.updateAnimal(selectedAnimal)
            }
            dismiss()
        } catch {
            errorMessage = NSLocalizedString("profile.save.error", comment: "")
        }
        isSaving = false
    }
}

// MARK: - 닉네임 변경 시트
struct NicknameEditorSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var nickname = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("profile.nickname")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("profile.nickname", text: $nickname)
                        .font(.system(size: 18, weight: .medium))
                        .padding()
                        .background(Color.systemGray6)
                        .cornerRadius(12)
                        .focused($isFocused)
                        .onChange(of: nickname) { _, new in
                            nickname = new.truncatedToNicknameWidth()
                        }
                    HStack {
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(nickname.displayWidth)/\(String.nicknameMaxWidth)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("common.save").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(nickname.trimmingCharacters(in: .whitespaces).count < 2 ? Color.systemGray4 : Color.tableInk)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
                .disabled(nickname.trimmingCharacters(in: .whitespaces).count < 2)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("profile.nickname")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear {
                nickname = authService.currentUser?.nickname ?? ""
                isFocused = true
            }
        }
    }

    private func save() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isLoading = true
        errorMessage = ""
        do {
            try await authService.updateNickname(trimmed)
            dismiss()
        } catch {
            errorMessage = NSLocalizedString("profile.save.error", comment: "")
        }
        isLoading = false
    }
}

// MARK: - 동물 선택 시트
struct AnimalPickerSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var selected: UserModel.AnimalType = .cat
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 선택된 캐릭터 미리보기
                CharacterImageView(
                    animal: selected,
                    activity: nil,
                    animated: true
                )
                    .frame(width: 100, height: 100)
                    .padding(.top, 24)
                    .animation(.spring(duration: 0.3), value: selected)

                Text(LocalizedStringKey(selected.displayKey))
                    .font(.title3)
                    .fontWeight(.semibold)

                // 동물 선택 그리드 (보유한 동물만)
                let ownedAnimals = UserModel.AnimalType.allCases.filter {
                    authService.currentUser?.ownsAnimal($0) ?? $0.isFree
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                    ForEach(ownedAnimals, id: \.self) { animal in
                        AnimalSelectCard(animal: animal, isSelected: selected == animal) {
                            selected = animal
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("common.save")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.tableInk)
                    .foregroundStyle(Color.tableInverseInk)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("profile.character")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear {
                selected = authService.currentUser?.animal ?? .cat
            }
        }
    }

    private func save() async {
        isLoading = true
        await authService.updateAnimal(selected)
        isLoading = false
        dismiss()
    }
}
