//
//  RoomListView.swift
//  table
//

import SwiftUI

struct RoomListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var roomService: RoomService
    @EnvironmentObject var broadcastService: BroadcastService
    @State private var showJoinRoom = false
    @State private var showCreateRoom = false
    @State private var showInbox = false
    @State private var selectedRoom: RoomModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 헤더
                    HStack {
                        Text("FocusPaws")
                            .font(.system(size: 24, weight: .bold))

                        Spacer()

                        HStack(spacing: 16) {
                            Button { showInbox = true } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "bell").fontWeight(.semibold)
                                    if broadcastService.unreadCount > 0 {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 3, y: -3)
                                    }
                                }
                            }
                            if roomService.myRooms.count < 2 {
                                Button { showCreateRoom = true } label: {
                                    Image(systemName: "plus").fontWeight(.semibold)
                                }
                            }
                            Button { showJoinRoom = true } label: {
                                Image(systemName: "person.badge.plus").fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.top, 4)

                    myRoomSection
                    if !roomService.friendRooms.isEmpty {
                        friendRoomsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showInbox) {
                MessageInboxView()
                    .environmentObject(authService)
                    .environmentObject(broadcastService)
            }
            .sheet(isPresented: $showJoinRoom) { JoinRoomSheet() }
            .sheet(isPresented: $showCreateRoom) { CreateRoomSheet() }
            .navigationDestination(item: $selectedRoom) { room in
                RoomView(room: room)
            }
            .onChange(of: roomService.deepLinkRoomId) { _, roomId in
                guard let roomId else { return }
                let all = roomService.myRooms + roomService.friendRooms
                if let room = all.first(where: { $0.id == roomId }) {
                    selectedRoom = room
                }
                roomService.deepLinkRoomId = nil
            }
        }
    }


    // MARK: - 내 방
    var myRoomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("room.my")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if roomService.myRooms.isEmpty {
                Button { showCreateRoom = true } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("room.create").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.systemGray6)
                    .foregroundStyle(.primary)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(roomService.myRooms) { room in
                    MyRoomCard(room: room) { selectedRoom = room }
                }
            }
        }
    }

    // MARK: - 친구 방
    var friendRoomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("room.friends")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(roomService.friendRooms) { room in
                FriendRoomCard(room: room) { selectedRoom = room }
            }
        }
    }
}

// MARK: - 내 방 카드
struct MyRoomCard: View {
    let room: RoomModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 17, weight: .bold))
                    Text("room.members \("\(room.memberIds.count)/\(maxRoomMembers)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "house.fill").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.tableInk)
            .foregroundStyle(Color.tableInverseInk)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 친구 방 카드
struct FriendRoomCard: View {
    let room: RoomModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 17, weight: .semibold))
                    Text("room.members \("\(room.memberIds.count)/\(maxRoomMembers)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.systemGray6)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 방 만들기 시트
struct CreateRoomSheet: View {
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "house.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("room.create.new").font(.title2).fontWeight(.bold)
                    Text("room.create.hint").foregroundStyle(.secondary)
                }

                TextField("room.name.placeholder", text: $name)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.systemGray6)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                    .onChange(of: name) { _, new in name = String(new.prefix(20)) }

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await createRoom() }
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("common.create").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.systemGray4 : Color.tableInk)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("room.create")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    private func createRoom() async {
        isLoading = true
        errorMessage = ""
        do {
            _ = try await roomService.createRoom(name: name.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 초대 코드 입력
struct JoinRoomSheet: View {
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var joined = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "key.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("room.join.code.title").font(.title2).fontWeight(.bold)
                    Text("room.join.hint").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                TextField("room.join.placeholder", text: $code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .tracking(6)
                    .autocapitalization(.allCharacters)
                    .padding()
                    .background(Color.systemGray6)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                    .onChange(of: code) { _, new in code = String(new.prefix(6)).uppercased() }

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                if joined {
                    Label("room.joined", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).fontWeight(.semibold)
                }

                Spacer()

                Button {
                    Task { await joinRoom() }
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("room.visit").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(code.count < 6 ? Color.systemGray4 : Color.tableInk)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }
                .disabled(code.count < 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("room.join.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    private func joinRoom() async {
        isLoading = true
        errorMessage = ""
        do {
            _ = try await roomService.joinRoom(inviteCode: code)
            joined = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
