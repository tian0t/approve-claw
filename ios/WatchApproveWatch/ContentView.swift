import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    var body: some View {
        ZStack {
            // Liquid Glass Dark Background
            Color(hex: "08080C").ignoresSafeArea()
            
            // Ambient glowing lights behind card
            Circle()
                .fill(RadialGradient(colors: [Color.blue.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: -35, y: -45)
            
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "D07058").opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: 35, y: 40)
            
            // ScrollView for full responsiveness across watch display sizes (40mm to 49mm Ultra)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    // Top Interactive Mecha Cat Pet Header
                    WatchTopPetHeader(connectionStatus: connectivity.connectionStatus)
                    
                    // Connection Status Pill
                    statusHeader
                    
                    if let request = connectivity.activeRequest {
                        requestView(request: request)
                    } else {
                        waitingView
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Watch Status Header
    private var statusHeader: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectivity.connectionStatus == "Connected" ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            
            Text(connectivity.connectionStatus)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            if !connectivity.macIP.isEmpty {
                Spacer()
                Text("Mac: \(connectivity.macIP)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }
    
    // MARK: - Waiting State View with English Connection Guide
    private var waitingView: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("CLAW Ready")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Listening for execution prompts...")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 2)
            
            // 3-step Connection Guide for Watch (English)
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Guide")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "D07058"))
                    .frame(maxWidth: .infinity, alignment: .center)
                
                watchStepRow(num: "1", text: "Run 'watchapprove' on Mac")
                watchStepRow(num: "2", text: "Pair IP & PIN on iPhone")
                watchStepRow(num: "3", text: "Watch receives requests live")
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
    
    private func watchStepRow(num: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(num)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 15, height: 15)
                .background(Color(hex: "D07058"))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Active Request View
    private func requestView(request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Agent Header & Risk
            HStack {
                HStack(spacing: 4) {
                    ClaudeMascotView()
                        .frame(width: 20, height: 14)
                    Text(request.agent)
                        .font(.system(size: 12, weight: .bold))
                }
                
                Spacer()
                
                riskBadge(risk: request.risk)
            }
            
            // Dynamic Single-Line Option Buttons for Apple Watch
            VStack(spacing: 6) {
                ForEach(request.dynamicOptions) { opt in
                    WatchOptionButtonRow(opt: opt) {
                        connectivity.sendDecision(requestId: request.id, action: opt.key)
                    }
                }
            }
            
            // Command Code Block - placed BELOW buttons
            Text(request.command)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    // MARK: - Risk Badge Helper
    private func riskBadge(risk: String) -> some View {
        let color: Color
        let text: String
        
        switch risk.lowercased() {
        case "high":
            color = .red
            text = "HIGH"
        case "medium":
            color = .orange
            text = "MED"
        default:
            color = .green
            text = "LOW"
        }
        
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Top Interactive Mecha Cat Pet Stage for Watch
struct WatchTopPetHeader: View {
    let connectionStatus: String
    
    @State private var petOffset: CGFloat = 0
    @State private var isFacingLeft: Bool = false
    @State private var tilt: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var speechBubble: String? = "Tap me! 🐾"
    
    private let speechOptions = [
        "CLAW Ready! 🤖",
        "Listening...",
        "Beep Boop! ⚡️",
        "Tap to Jump! 💃",
        "Protected 🛡️"
    ]
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "D07058").opacity(0.4), .clear, Color.blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            VStack(spacing: 4) {
                if let text = speechBubble {
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "D07058"))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                
                ClaudeMascotView()
                    .frame(width: 44, height: 28)
                    .rotationEffect(.degrees(tilt))
                    .scaleEffect(x: (isFacingLeft ? -1 : 1) * scale, y: scale)
                    .offset(x: petOffset)
                    .onTapGesture {
                        triggerRandomAction()
                    }
            }
            .padding(.vertical, 8)
        }
        .frame(height: 72)
    }
    
    private func triggerRandomAction() {
        WKInterfaceDevice.current().play(.click)
        
        let randomChoice = Int.random(in: 0...3)
        speechBubble = speechOptions.randomElement()
        
        switch randomChoice {
        case 0:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                scale = 1.3
                tilt = -15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { scale = 1.0; tilt = 0 }
            }
        case 1:
            withAnimation(.easeInOut(duration: 0.4)) {
                tilt = 360
                isFacingLeft.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                tilt = 0
            }
        case 2:
            withAnimation(.easeInOut(duration: 0.3)) {
                petOffset = (petOffset > 0) ? -20 : 20
                isFacingLeft = petOffset < 0
            }
        default:
            withAnimation(.easeInOut(duration: 0.15).repeatCount(4, autoreverses: true)) {
                tilt = 10
                scale = 1.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                scale = 1.0
                tilt = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                speechBubble = nil
            }
        }
    }
}

// MARK: - Mecha Cat Mascot View
struct ClaudeMascotView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 12
            let h = geo.size.height / 10
            
            ZStack(alignment: .topLeading) {
                // Cybernetic Blue Armor Head & Collar (#1F4773)
                Group {
                    Rectangle()
                        .fill(Color(hex: "18385A"))
                        .frame(width: w * 3, height: h * 3)
                        .offset(x: w * 1, y: 0)
                    
                    Rectangle()
                        .fill(Color(hex: "18385A"))
                        .frame(width: w * 3, height: h * 3)
                        .offset(x: w * 8, y: 0)
                    
                    Rectangle()
                        .fill(Color(hex: "245486"))
                        .frame(width: w * 8, height: h * 6)
                        .offset(x: w * 2, y: h * 2)
                    
                    Rectangle()
                        .fill(Color(hex: "3472B2"))
                        .frame(width: w * 2, height: h * 3)
                        .offset(x: 0, y: h * 3)
                    
                    Rectangle()
                        .fill(Color(hex: "3472B2"))
                        .frame(width: w * 2, height: h * 3)
                        .offset(x: w * 10, y: h * 3)
                    
                    Rectangle()
                        .fill(Color(hex: "152F4F"))
                        .frame(width: w * 6, height: h * 2)
                        .offset(x: w * 3, y: h * 8)
                }
                
                // Glowing Neon Orange Slanted Cat Eyes (#FF8800)
                Group {
                    Rectangle()
                        .fill(Color(hex: "FF8800"))
                        .frame(width: w * 2, height: h * 1.5)
                        .offset(x: w * 3.5, y: h * 3.5)
                    
                    Rectangle()
                        .fill(Color(hex: "FF8800"))
                        .frame(width: w * 2, height: h * 1.5)
                        .offset(x: w * 6.5, y: h * 3.5)
                }
            }
        }
    }
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8 * 17) & 0xff, (int >> 4 & 0xf * 17) & 0xff, (int & 0xf * 17) & 0xff)
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xff, (int >> 8) & 0xff, (int & 0xff) & 0xff)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xff, (int >> 16) & 0xff, (int >> 8) & 0xff, (int & 0xff) & 0xff)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Watch Option Button Row Subview
struct WatchOptionButtonRow: View {
    let opt: ApprovalOption
    let action: () -> Void
    
    private var textColor: Color {
        if opt.isDestructive { return .red }
        if opt.isPrimary { return .white }
        return .white.opacity(0.9)
    }
    
    private var iconName: String {
        if opt.isDestructive { return "xmark.circle.fill" }
        if opt.isPrimary { return "checkmark.circle.fill" }
        return "chevron.right.circle"
    }
    
    private var iconColor: Color {
        if opt.isDestructive { return .red }
        if opt.isPrimary { return .green }
        return .white.opacity(0.5)
    }
    
    private var backgroundColor: Color {
        if opt.isPrimary { return .blue }
        if opt.isDestructive { return Color.red.opacity(0.15) }
        return Color.white.opacity(0.08)
    }
    
    private var strokeColor: Color {
        if opt.isDestructive { return Color.red.opacity(0.3) }
        if opt.isPrimary { return Color.blue.opacity(0.5) }
        return Color.white.opacity(0.12)
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(opt.label)
                    .font(.system(size: 11, weight: opt.isPrimary ? .bold : .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
