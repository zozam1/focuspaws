//
//  RoomView.swift
//  table
//

import SwiftUI
import Combine

let maxRoomMembers = 6

struct RoomView: View {
    let room: RoomModel
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var showInviteCode = false
    @State private var showStatusEditor = false
    @State private var showLeaveAlert = false
    @State private var showCustomization = false
    @State private var showRenameSheet = false
    @State private var showMemberManage = false
    @State private var showDeleteAlert = false
    @State private var currentRoomName: String = ""

    var isMyRoom: Bool {
        liveRoom.createdBy == authService.currentUser?.id
    }

    private var liveRoom: RoomModel {
        roomService.activeRoom ?? room
    }

    var body: some View {
        RoomTableView(
            members: roomService.currentRoomMembers,
            currentUserId: authService.currentUser?.id ?? "",
            roomStatusMessages: roomService.roomStatusMessages,
            equippedLayout: .defaultHoneyBakery,
            selectedRoomSkin: RoomSkinCatalog.skin(id: liveRoom.selectedRoomSkinId)
        )
        .navigationTitle(currentRoomName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white.opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isMyRoom {
                        Button { showCustomization = true } label: {
                            Image(systemName: "paintpalette")
                        }
                    }
                    Button { showStatusEditor = true } label: {
                        Image(systemName: "bubble.left")
                    }
                    if isMyRoom {
                        Menu {
                            Button {
                                showInviteCode = true
                            } label: {
                                Label("room.invite.code", systemImage: "link")
                            }
                            Button {
                                showRenameSheet = true
                            } label: {
                                Label("room.rename", systemImage: "pencil")
                            }
                            Button {
                                showMemberManage = true
                            } label: {
                                Label("room.manage", systemImage: "person.2")
                            }
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("room.delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveAlert = true
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteCode) {
            InviteCodeSheet(inviteCode: liveRoom.inviteCode)
        }
        .sheet(isPresented: $showStatusEditor) {
            RoomStatusSheet(roomId: room.id)
        }
        .sheet(isPresented: $showCustomization) {
            TableCustomizationView(room: liveRoom)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameRoomSheet(room: liveRoom, currentName: $currentRoomName)
        }
        .sheet(isPresented: $showMemberManage) {
            MemberManageSheet(room: liveRoom)
        }
        .alert("room.leave.title", isPresented: $showLeaveAlert) {
            Button("common.cancel", role: .cancel) {}
            Button("room.leave", role: .destructive) {
                Task {
                    try? await roomService.leaveRoom(liveRoom)
                    dismiss()
                }
            }
        } message: {
            Text("room.leave.confirm")
        }
        .alert("room.delete", isPresented: $showDeleteAlert) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                Task {
                    try? await roomService.deleteRoom(liveRoom)
                    dismiss()
                }
            }
        } message: {
            Text("room.delete.confirm")
        }
        .onAppear {
            currentRoomName = room.name
            roomService.listenToRoom(id: room.id)
            roomService.listenToMembers(of: room)
            roomService.listenToRoomStatus(roomId: room.id)
        }
        .onChange(of: roomService.activeRoom?.name) { _, newName in
            if let newName { currentRoomName = newName }
        }
        .onChange(of: roomService.activeRoom?.id) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                dismiss()
            }
        }
        .onChange(of: roomService.activeRoom?.memberIds) { _, memberIds in
            guard let myId = authService.currentUser?.id, let memberIds else { return }
            if !memberIds.contains(myId) {
                dismiss()
            }
        }
    }
}

// MARK: - 책상 위 미니어처 월드
struct RoomTableView: View {
    let members: [UserModel]
    let currentUserId: String
    let roomStatusMessages: [String: String]
    var equippedLayout: EquippedTableLayout = .defaultHoneyBakery
    var selectedRoomSkin: RoomSkin = RoomSkinCatalog.all[0]
    var onMemberTap: ((UserModel) -> Void)? = nil

    @State private var selectedMember: UserModel?

    private var orderedMembers: [UserModel] {
        guard let me = members.first(where: { $0.id == currentUserId }) else { return members }
        let others = members.filter { $0.id != currentUserId }
        return [me] + others
    }

    private var desktopMembers: [UserModel] {
        Array(orderedMembers.prefix(maxRoomMembers))
    }

    var body: some View {
        ZStack {
            deskRoomBackground

            DeskWorldView(
                members: desktopMembers,
                currentUserId: currentUserId,
                roomStatusMessages: roomStatusMessages,
                skin: selectedRoomSkin,
                onMemberTap: { member in
                    if let onMemberTap {
                        onMemberTap(member)
                    } else {
                        selectedMember = member
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .sheet(item: $selectedMember) { member in
            MemberProfileSheet(member: member)
        }
    }

    private var deskRoomBackground: some View {
        ZStack {
            Image(selectedRoomSkin.deskPhotoAssetName)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(selectedRoomSkin.id == "charcoal" ? 0.18 : 0.00))

            LinearGradient(
                colors: [Color.black.opacity(0.00), Color.black.opacity(selectedRoomSkin.id == "charcoal" ? 0.22 : 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

}

struct DeskWorldView: View {
    let members: [UserModel]
    let currentUserId: String
    let roomStatusMessages: [String: String]
    let skin: RoomSkin
    var onMemberTap: ((UserModel) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let count = members.count

            ZStack {
                ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                    let point = slotPosition(index: index, count: count)
                    let size = slotSize(for: count)
                    let badgeSide: DesktopAnimalSlotView.BadgeSide = {
                        if count == 4 && index >= 2 { return .bottom }
                        if count == 5 {
                            switch index {
                            case 3, 4: return .bottom
                            default: return .top
                            }
                        }
                        if count == 6 {
                            return index >= 3 ? .bottom : .top
                        }
                        return .top
                    }()
                    DesktopAnimalSlotView(
                        member: member,
                        currentUserId: currentUserId,
                        statusMessage: roomStatusMessages[member.id],
                        slotIndex: index,
                        skin: skin,
                        isMirrored: point.x < 0.50,
                        badgeMaxWidth: .infinity,
                        badgeSide: badgeSide
                    )
                    .frame(width: size.width, height: size.height)
                    .position(x: width * point.x, y: height * point.y)
                    .zIndex(Double(point.y * 100 + CGFloat(index)))
                    .onTapGesture { onMemberTap?(member) }
                }
            }
        }
    }

    private func slotPosition(index: Int, count: Int) -> CGPoint {
        let layouts: [[CGPoint]] = [
            [CGPoint(x: 0.50, y: 0.52)],
            [CGPoint(x: 0.32, y: 0.64), CGPoint(x: 0.68, y: 0.64)],
            [CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.28, y: 0.68), CGPoint(x: 0.72, y: 0.68)],
            [CGPoint(x: 0.28, y: 0.50), CGPoint(x: 0.72, y: 0.50), CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.72, y: 0.72)],
            [CGPoint(x: 0.50, y: 0.44), CGPoint(x: 0.22, y: 0.58), CGPoint(x: 0.78, y: 0.58), CGPoint(x: 0.28, y: 0.80), CGPoint(x: 0.72, y: 0.80)],
            [CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.80, y: 0.50),
             CGPoint(x: 0.20, y: 0.74), CGPoint(x: 0.50, y: 0.84), CGPoint(x: 0.80, y: 0.74)]
        ]
        let safeCount = min(max(count, 1), layouts.count)
        let layout = layouts[safeCount - 1]
        let point = layout[min(index, layout.count - 1)]
        return CGPoint(x: point.x, y: max(0.34, point.y - 0.045))
    }

    private func slotSize(for count: Int) -> CGSize {
        count == 1 ? CGSize(width: 178, height: 230) : CGSize(width: 146, height: 194)
    }
}

struct TableWorldView: View {
    let theme: TableTheme
    let skin: RoomSkin

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                DeskSurfaceShape()
                    .fill(Color.black.opacity(0.16))
                    .blur(radius: 18)
                    .offset(y: 24)
                    .padding(.horizontal, 6)

                DeskSurfaceShape()
                    .fill(
                        LinearGradient(
                            colors: skin.deskSurfaceColors.map { $0.opacity(0.72) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        DeskSurfaceShape()
                            .stroke(skin.deskEdgeColor.opacity(0.85), lineWidth: 2.4)
                    }
                    .overlay {
                        deskGrain(width: width, height: height)
                            .clipShape(DeskSurfaceShape())
                    }

                Capsule()
                    .fill(theme.runnerColor.opacity(0.42))
                    .frame(width: width * 0.48, height: height * 0.12)
                    .rotationEffect(.degrees(-2))
                    .position(x: width * 0.50, y: height * 0.49)
                    .blendMode(.softLight)

                tableDecor(width: width, height: height)
                    .opacity(0.82)
            }
            .padding(.top, height * 0.05)
        }
    }

    private func deskGrain(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8) { index in
                Capsule()
                    .fill(skin.deskLineColor.opacity(0.22))
                    .frame(width: width * CGFloat(0.34 + Double(index % 3) * 0.11), height: 1.2)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2 : 1.5))
                    .position(
                        x: width * CGFloat(0.16 + Double(index % 4) * 0.22),
                        y: height * CGFloat(0.24 + Double(index) * 0.075)
                    )
            }
        }
    }

    @ViewBuilder
    private func tableDecor(width: CGFloat, height: CGFloat) -> some View {
        switch theme.decorStyle {
        case .honeyBakery:
            decorRow(
                lamp: AnyView(HoneyLampIcon()),
                snack: AnyView(CookiePlateIcon()),
                drink: AnyView(MilkBottleIcon()),
                stationery: AnyView(PencilCupIcon()),
                miniLeft: AnyView(Circle().fill(Color(red: 0.98, green: 0.80, blue: 0.40))),
                miniRight: AnyView(FlowerIcon()),
                width: width,
                height: height
            )
        case .strawberryMilk:
            decorRow(
                lamp: AnyView(StrawberryLampIcon()),
                snack: AnyView(CakeIcon()),
                drink: AnyView(StrawberryMilkIcon()),
                stationery: AnyView(RibbonCupIcon()),
                miniLeft: AnyView(HeartIcon()),
                miniRight: AnyView(BowIcon()),
                width: width,
                height: height
            )
        case .forestPicnic:
            decorRow(
                lamp: AnyView(MushroomLampIcon()),
                snack: AnyView(AcornCookieIcon()),
                drink: AnyView(TeaCupIcon()),
                stationery: AnyView(BarkCupIcon()),
                miniLeft: AnyView(CloverIcon()),
                miniRight: AnyView(PineconeIcon()),
                width: width,
                height: height
            )
        case .moonlightStudy:
            decorRow(
                lamp: AnyView(MoonLampIcon()),
                snack: AnyView(MacaronIcon()),
                drink: AnyView(SodaIcon()),
                stationery: AnyView(SilverCupIcon()),
                miniLeft: AnyView(StarIcon()),
                miniRight: AnyView(CrystalIcon()),
                width: width,
                height: height
            )
        case .cloudCafe:
            decorRow(
                lamp: AnyView(BunnyLampIcon()),
                snack: AnyView(SconeIcon()),
                drink: AnyView(LatteIcon()),
                stationery: AnyView(PastelCupIcon()),
                miniLeft: AnyView(SugarJarIcon()),
                miniRight: AnyView(CloudIcon()),
                width: width,
                height: height
            )
        }
    }

    private func decorRow(
        lamp: AnyView,
        snack: AnyView,
        drink: AnyView,
        stationery: AnyView,
        miniLeft: AnyView,
        miniRight: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Group {
            lamp.frame(width: 34, height: 46).position(x: width * 0.13, y: height * 0.33)
            snack.frame(width: 38, height: 24).position(x: width * 0.35, y: height * 0.70)
            drink.frame(width: 24, height: 40).position(x: width * 0.69, y: height * 0.69)
            stationery.frame(width: 30, height: 38).position(x: width * 0.88, y: height * 0.36)
            miniLeft.frame(width: 16, height: 16).position(x: width * 0.21, y: height * 0.52)
            miniRight.frame(width: 16, height: 16).position(x: width * 0.77, y: height * 0.52)
        }
    }
}

private struct DeskSurfaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topInset = rect.width * 0.07
        let bottomInset = rect.width * 0.01
        let topY = rect.height * 0.12
        let bottomY = rect.height * 0.94

        path.move(to: CGPoint(x: rect.minX + topInset, y: topY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - topInset, y: topY), control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomInset, y: bottomY), control: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + bottomInset, y: bottomY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.03))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topInset, y: topY), control: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.midY))
        return path
    }
}

struct DeskRoomProps: View {
    let skin: RoomSkin

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PlantProp()
                    .frame(width: 86, height: 112)
                    .blur(radius: 0.2)
                    .position(x: geo.size.width * 0.13, y: geo.size.height * 0.16)
                    .opacity(skin.id == "charcoal" ? 0.58 : 0.82)

                CableProp()
                    .stroke(Color.white.opacity(skin.id == "charcoal" ? 0.22 : 0.62), lineWidth: 8)
                    .frame(width: 136, height: 72)
                    .position(x: geo.size.width * 0.86, y: geo.size.height * 0.20)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(skin.id == "charcoal" ? 0.10 : 0.42))
                    .frame(width: 128, height: 58)
                    .rotationEffect(.degrees(-10))
                    .position(x: geo.size.width * 0.10, y: geo.size.height * 0.88)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 4)
            }
        }
    }
}

private struct PlantProp: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<7) { index in
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 0.36), Color(red: 0.25, green: 0.46, blue: 0.27)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 18, height: 52)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index - 3) * 22))
            }
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.86))
                .frame(width: 54, height: 48)
                .shadow(color: .black.opacity(0.08), radius: 7, y: 4)
        }
    }
}

private struct CableProp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY - rect.height * 0.25),
            control2: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.maxY + rect.height * 0.25)
        )
        return path
    }
}

struct FocusSessionDial: View {
    let activity: ActivityStatus?
    let skin: RoomSkin
    @State private var timeText = "00:00"
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(skin.id == "charcoal" ? 0.90 : 0.82))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)

            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 8)

            Circle()
                .trim(from: 0.04, to: 0.34)
                .stroke(Color(red: 0.38, green: 0.68, blue: 0.93), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.48, to: 0.78)
                .stroke(Color(red: 0.33, green: 0.79, blue: 0.66), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.82))

                Capsule()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 74, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.35, green: 0.76, blue: 0.81))
                            .frame(width: 46, height: 6)
                    }
            }
        }
        .onReceive(timer) { _ in updateTime() }
        .onAppear { updateTime() }
    }

    private func updateTime() {
        if let activity {
            timeText = activity.elapsedString
        } else {
            timeText = "00:00"
        }
    }
}

private struct DesktopAnimalSlotView: View {
    enum BadgeSide { case top, bottom, left, right }

    let member: UserModel
    let currentUserId: String
    let statusMessage: String?
    let slotIndex: Int
    let skin: RoomSkin
    let isMirrored: Bool
    var badgeMaxWidth: CGFloat = 120
    var badgeSide: BadgeSide = .top

    private var character: some View {
        ActiveSeatCharacter(member: member, mirrored: isMirrored, showsContactShadow: true)
            .frame(width: 132, height: 112, alignment: .bottom)
    }

    var body: some View {
        switch badgeSide {
        case .top:
            VStack(spacing: 1) {
                statusBubble
                nameTimerBadge
                character
            }
        case .bottom:
            VStack(spacing: 1) {
                character
                nameTimerBadge
                statusBubble
            }
        case .right:
            // 뱃지를 캐릭터 오른쪽(화면 바깥) 방향으로
            VStack(spacing: 1) {
                character
                    .overlay(alignment: .trailing) {
                        sideBadge
                            .alignmentGuide(.trailing) { d in d[.leading] - 2 }
                    }
            }
        case .left:
            // 뱃지를 캐릭터 왼쪽(화면 바깥) 방향으로
            VStack(spacing: 1) {
                character
                    .overlay(alignment: .leading) {
                        sideBadge
                            .alignmentGuide(.leading) { d in d[.trailing] + 2 }
                    }
            }
        }
    }

    private var sideBadge: some View {
        VStack(spacing: 3) {
            nameTimerBadge
            statusBubble
        }
    }

    private var nameTimerBadge: some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Text(member.nickname)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                if member.id == currentUserId {
                    Text("label.me")
                        .font(.system(size: 7, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            if let activity = member.currentActivity {
                ActivityTimerLabel(activity: activity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .fixedSize()
        .background(Color.white.opacity(skin.id == "charcoal" ? 0.82 : 0.76), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.62), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 5, y: 3)
    }

    @ViewBuilder
    private var statusBubble: some View {
        if let statusMessage, !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.90), in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        }
    }
}

private struct HoneyLampIcon: View {
    var body: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 1.00, green: 0.85, blue: 0.42))
                .frame(width: 28, height: 24)
                .overlay(Circle().fill(Color.white.opacity(0.35)).frame(width: 10, height: 10))
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.57, green: 0.36, blue: 0.19))
                .frame(width: 6, height: 18)
        }
    }
}

private struct CookiePlateIcon: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.92))
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle().fill(Color(red: 0.78, green: 0.55, blue: 0.29))
                }
            }
            .padding(5)
        }
    }
}

private struct MilkBottleIcon: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.96, green: 0.90, blue: 0.82))
                .frame(width: 12, height: 10)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.99, green: 0.97, blue: 0.93))
                .frame(width: 24, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.83, green: 0.75, blue: 0.67), lineWidth: 1))
        }
    }
}

private struct PencilCupIcon: View {
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 3) {
                Capsule().fill(Color(red: 0.86, green: 0.49, blue: 0.37))
                Capsule().fill(Color(red: 0.95, green: 0.71, blue: 0.31))
                Capsule().fill(Color(red: 0.54, green: 0.66, blue: 0.45))
            }
            .frame(width: 24, height: 28)
            .offset(y: -8)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.68, green: 0.46, blue: 0.27))
                .frame(width: 30, height: 28)
                .offset(y: 8)
        }
    }
}

private struct FlowerIcon: View {
    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Circle()
                    .fill(Color(red: 1.00, green: 0.92, blue: 0.70))
                    .frame(width: 8, height: 8)
                    .offset(y: -5)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle().fill(Color(red: 0.92, green: 0.65, blue: 0.28)).frame(width: 6, height: 6)
        }
    }
}

// MARK: - 빈 자리
struct EmptySeatView: View {
    let flipped: Bool

    var body: some View {
        VStack(spacing: 4) {
            if flipped {
                Color.clear.frame(height: 16)
                placeholder
                Color.clear.frame(height: 24)
            } else {
                Color.clear.frame(height: 24)
                placeholder
                Color.clear.frame(height: 16)
            }
        }
        .frame(width: 88)
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.60))
                .frame(width: 46, height: 46)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.black.opacity(0.16))
        }
    }
}

// MARK: - 자리 (멤버 있으면 캐릭터, 없으면 공석)
struct SeatView: View {
    let member: UserModel
    let currentUserId: String
    let flipped: Bool
    let statusMessage: String?

    var body: some View {
        VStack(spacing: 4) {
            if flipped {
                statusBubble
                ActiveSeatCharacter(member: member)
                nicknameLabel
            } else {
                nicknameLabel
                ActiveSeatCharacter(member: member)
                statusBubble
            }
        }
        .frame(width: 88)
    }

    @ViewBuilder
    var statusBubble: some View {
        if let status = statusMessage, !status.isEmpty {
            Text(status)
                .font(.system(size: 9))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.tableSecondaryBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.systemGray5, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 2)
        } else {
            Color.clear.frame(height: 16)
        }
    }

    @ViewBuilder
    var nicknameLabel: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(member.nickname)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if member.id == currentUserId {
                    Text("label.me")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.tableInk)
                        .foregroundStyle(Color.tableInverseInk)
                        .cornerRadius(3)
                }
            }
            if let activity = member.currentActivity {
                ActivityTimerLabel(activity: activity)
            }
        }
    }
}

// MARK: - 방 상태메시지 시트
struct RoomStatusSheet: View {
    let roomId: String
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var message = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

    let suggestions = ["room.status.focus", "room.status.deadline", "room.status.run", "room.status.tired", "room.status.coffee"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("room.status.placeholder", text: $message)
                        .font(.system(size: 17))
                        .padding()
                        .background(Color.systemGray6)
                        .cornerRadius(12)
                        .focused($isFocused)
                        .onChange(of: message) { _, new in
                            if new.count > 30 { message = String(new.prefix(30)) }
                        }
                    Text("\(message.count)/30")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { message = NSLocalizedString(s, comment: "") } label: {
                                Text(LocalizedStringKey(s))
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.systemGray6)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isLoading { ProgressView().tint(.white) }
                            else { Text("common.save").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.tableInk).foregroundStyle(Color.tableInverseInk).cornerRadius(14)
                    }

                    Button("room.status.clear") {
                        Task {
                            await roomService.setRoomStatusMessage(roomId: roomId, message: nil)
                            dismiss()
                        }
                    }
                    .foregroundStyle(.red)
                    .font(.subheadline)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("room.status.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear {
                let uid = authService.currentUser?.id ?? ""
                message = roomService.roomStatusMessages[uid] ?? ""
                isFocused = true
            }
        }
    }

    private func save() async {
        isLoading = true
        await roomService.setRoomStatusMessage(roomId: roomId, message: message.isEmpty ? nil : message)
        isLoading = false
        dismiss()
    }
}

private struct CharacterContactShadow: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.34, green: 0.24, blue: 0.16).opacity(0.18))
                .frame(width: 96, height: 18)
                .blur(radius: 5.8)

            Ellipse()
                .fill(Color(red: 0.20, green: 0.15, blue: 0.11).opacity(0.075))
                .frame(width: 68, height: 9)
                .blur(radius: 2.0)
                .offset(y: -1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 활동 중인 캐릭터
struct ActiveSeatCharacter: View {
    let member: UserModel
    var mirrored: Bool = false
    var displayScale: CGFloat = 1.0
    var showsContactShadow: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            if showsContactShadow {
                CharacterContactShadow()
                    .offset(y: -3)
            }

            CharacterImageView(
                animal: member.animal,
                activity: member.currentActivity?.type,
                animated: true
            )
            .frame(width: 90, height: 90)
            .scaleEffect(x: mirrored ? -displayScale : displayScale, y: displayScale)
            .frame(width: 102, height: 102, alignment: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
            activityBadge
        }
        .frame(width: 126, height: 126, alignment: .bottom)
    }

    @ViewBuilder
    private var activityBadge: some View {
        if let activity = member.currentActivity {
            Image(systemName: activity.type.sfSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: activity.type.color) ?? .blue)
                .padding(5)
                .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 3))
                .offset(x: 5, y: 0)
        }
    }
}

// MARK: - 활동 타이머 라벨
struct ActivityTimerLabel: View {
    let activity: ActivityStatus
    @State private var elapsed = ""
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if activity.type != .resting {
            Text(elapsed)
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: activity.type.color) ?? .blue)
                .onReceive(timer) { _ in elapsed = activity.elapsedString }
                .onAppear { elapsed = activity.elapsedString }
        }
    }
}

// MARK: - 동물 폴백
struct AnimalEmojiView: View {
    let member: UserModel

    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 40))
            .foregroundStyle(.secondary)
    }
}

// MARK: - 방 이름 변경 시트
struct RenameRoomSheet: View {
    let room: RoomModel
    @Binding var currentName: String
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var isLoading = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                TextField("room.name.placeholder", text: $name)
                    .font(.system(size: 20, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.systemGray6)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                    .focused($isFocused)
                    .onChange(of: name) { _, new in
                        name = String(new.prefix(20))
                    }

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
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.systemGray4 : Color.tableInk)
                    .foregroundStyle(Color.tableInverseInk)
                    .cornerRadius(14)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("room.rename")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear {
                name = room.name
                isFocused = true
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        do {
            try await roomService.updateRoomName(trimmed, for: room)
            currentName = trimmed
            dismiss()
        } catch {
            print("방 이름 변경 실패: \(error)")
        }
        isLoading = false
    }
}

// MARK: - 멤버 관리 시트 (방장 전용)
struct MemberManageSheet: View {
    let room: RoomModel
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var roomService: RoomService
    @Environment(\.dismiss) var dismiss
    @State private var kickTargetId: String?
    @State private var showKickAlert = false

    var members: [UserModel] { roomService.currentRoomMembers }
    var myId: String { authService.currentUser?.id ?? "" }

    var body: some View {
        NavigationStack {
            List {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        CharacterImageView(
                            animal: member.animal,
                            activity: nil
                        )
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.nickname)
                                    .fontWeight(.medium)
                                if member.id == myId {
                                    Text("label.me")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.tableInk)
                                        .foregroundStyle(Color.tableInverseInk)
                                        .cornerRadius(4)
                                }
                                if member.id == room.createdBy {
                                    Text("label.owner")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(4)
                                }
                            }
                            Text(LocalizedStringKey(member.animal.displayKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if member.id != myId {
                            Button {
                                kickTargetId = member.id
                                showKickAlert = true
                            } label: {
                                Image(systemName: "person.badge.minus")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("room.manage")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.close") { dismiss() }
                }
            }
            .alert("room.kick.title", isPresented: $showKickAlert) {
                Button("common.cancel", role: .cancel) {}
                Button("room.kick", role: .destructive) {
                    guard let targetId = kickTargetId else { return }
                    Task {
                        try? await roomService.kickMember(targetId, from: room)
                    }
                }
            } message: {
                let name = members.first(where: { $0.id == kickTargetId })?.nickname ?? ""
                Text("room.kick.confirm \(name)")
            }
        }
    }
}

// MARK: - 초대 코드 시트
struct InviteCodeSheet: View {
    let inviteCode: String
    @Environment(\.dismiss) var dismiss
    @State private var copied = false

    private var shareText: String {
        String(format: NSLocalizedString("room.invite.share.text %@", comment: ""), inviteCode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("room.invite.code")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("room.invite.hint")
                    .foregroundStyle(.secondary)

                Text(inviteCode)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .tracking(10)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 32)
                    .background(Color.systemGray6)
                    .cornerRadius(16)

                VStack(spacing: 12) {
                    ShareLink(item: shareText) {
                        Label("common.share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = inviteCode
                        #endif
                        copied = true
                    } label: {
                        Label(copied ? "room.invite.copied" : "room.invite.copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(copied ? Color.green.opacity(0.12) : Color.systemGray6)
                            .foregroundStyle(copied ? .green : .primary)
                            .cornerRadius(12)
                            .animation(.spring, value: copied)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }
}


private struct StrawberryLampIcon: View {
    var body: some View {
        VStack(spacing: 2) {
            Circle().fill(Color(red: 0.98, green: 0.40, blue: 0.49)).frame(width: 28, height: 28)
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.55, green: 0.38, blue: 0.28)).frame(width: 6, height: 18)
        }
    }
}
private struct CakeIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 1.00, green: 0.88, blue: 0.91)).overlay(Circle().fill(Color.red.opacity(0.7)).frame(width: 8, height: 8).offset(y: -8)) } }
private struct StrawberryMilkIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 1.00, green: 0.82, blue: 0.88)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1)) } }
private struct RibbonCupIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.95, green: 0.72, blue: 0.80)).overlay(BowIcon().frame(width: 12, height: 8)) } }
private struct HeartIcon: View { var body: some View { Image(systemName: "heart.fill").foregroundStyle(Color(red: 0.95, green: 0.48, blue: 0.59)) } }
private struct BowIcon: View { var body: some View { Image(systemName: "bowtie").foregroundStyle(Color(red: 0.85, green: 0.42, blue: 0.55)) } }
private struct MushroomLampIcon: View { var body: some View { VStack(spacing: 1) { Capsule().fill(Color(red: 0.86, green: 0.42, blue: 0.35)).frame(width: 28, height: 16); RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.77, green: 0.68, blue: 0.52)).frame(width: 8, height: 20) } } }
private struct AcornCookieIcon: View { var body: some View { Circle().fill(Color(red: 0.64, green: 0.42, blue: 0.22)).overlay(Capsule().fill(Color(red: 0.45, green: 0.31, blue: 0.18)).frame(width: 20, height: 8).offset(y: -8)) } }
private struct TeaCupIcon: View { var body: some View { Circle().trim(from: 0, to: 0.75).stroke(Color(red: 0.48, green: 0.60, blue: 0.35), lineWidth: 8) } }
private struct BarkCupIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.48, green: 0.35, blue: 0.24)) } }
private struct CloverIcon: View { var body: some View { Image(systemName: "leaf.fill").foregroundStyle(Color(red: 0.42, green: 0.62, blue: 0.35)) } }
private struct PineconeIcon: View { var body: some View { Image(systemName: "drop.fill").foregroundStyle(Color(red: 0.48, green: 0.34, blue: 0.22)) } }
private struct MoonLampIcon: View { var body: some View { Image(systemName: "moon.stars.fill").resizable().scaledToFit().foregroundStyle(Color(red: 1.00, green: 0.91, blue: 0.58)) } }
private struct MacaronIcon: View { var body: some View { HStack(spacing: 3) { Circle().fill(.white); Circle().fill(Color(red: 0.80, green: 0.77, blue: 0.98)); Circle().fill(Color(red: 0.72, green: 0.84, blue: 1.00)) } } }
private struct SodaIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.42, green: 0.45, blue: 0.79)) } }
private struct SilverCupIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.78, green: 0.79, blue: 0.86)) } }
private struct StarIcon: View { var body: some View { Image(systemName: "star.fill").foregroundStyle(Color(red: 1.00, green: 0.93, blue: 0.61)) } }
private struct CrystalIcon: View { var body: some View { Image(systemName: "diamond.fill").foregroundStyle(Color(red: 0.75, green: 0.90, blue: 1.00)) } }
private struct BunnyLampIcon: View { var body: some View { Image(systemName: "hare.fill").resizable().scaledToFit().foregroundStyle(Color(red: 1.00, green: 0.88, blue: 0.90)) } }
private struct SconeIcon: View { var body: some View { Circle().fill(Color(red: 0.78, green: 0.57, blue: 0.35)) } }
private struct LatteIcon: View { var body: some View { Circle().fill(Color(red: 0.73, green: 0.56, blue: 0.43)) } }
private struct PastelCupIcon: View { var body: some View { RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.72, green: 0.86, blue: 0.93)) } }
private struct SugarJarIcon: View { var body: some View { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.9)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.15), lineWidth: 1)) } }
private struct CloudIcon: View { var body: some View { Image(systemName: "cloud.fill").foregroundStyle(.white) } }

// MARK: - Preview Helpers
#if DEBUG
private func mockMember(id: String, nickname: String, animal: UserModel.AnimalType, activity: ActivityType? = nil) -> UserModel {
    UserModel(
        id: id,
        nickname: nickname,
        animal: animal,
        currentActivity: activity.map { ActivityStatus(type: $0, startedAt: Date().addingTimeInterval(-Double.random(in: 300...7200))) },
        createdAt: Date()
    )
}

private let previewSkin = RoomSkinCatalog.skin(id: "desk")

private let previewMembers: [UserModel] = [
    mockMember(id: "1", nickname: "하늘",  animal: .cat,     activity: .coding),
    mockMember(id: "2", nickname: "다온",  animal: .bear,    activity: .studying),
    mockMember(id: "3", nickname: "시우",  animal: .rabbit,  activity: .exercise),
    mockMember(id: "4", nickname: "루나",  animal: .hamster, activity: .working),
    mockMember(id: "5", nickname: "제이",  animal: .dog,     activity: nil),
    mockMember(id: "6", nickname: "솔이",  animal: .otter,   activity: .coding),
]

#Preview("1명") {
    DeskWorldView(members: Array(previewMembers.prefix(1)), currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 420).background(Color(hex: "#F5EFE4") ?? .gray)
}

#Preview("2명") {
    DeskWorldView(members: Array(previewMembers.prefix(2)), currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 420).background(Color(hex: "#F5EFE4") ?? .gray)
}

#Preview("3명") {
    DeskWorldView(members: Array(previewMembers.prefix(3)), currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 420).background(Color(hex: "#F5EFE4") ?? .gray)
}

#Preview("4명") {
    DeskWorldView(members: Array(previewMembers.prefix(4)), currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 460).background(Color(hex: "#F5EFE4") ?? .gray)
}

#Preview("5명") {
    DeskWorldView(members: Array(previewMembers.prefix(5)), currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 460).background(Color(hex: "#F5EFE4") ?? .gray)
}

#Preview("6명") {
    DeskWorldView(members: previewMembers, currentUserId: "1", roomStatusMessages: [:], skin: previewSkin)
        .frame(height: 500).background(Color(hex: "#F5EFE4") ?? .gray)
}
#endif
