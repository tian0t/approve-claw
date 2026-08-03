import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var wsManager = WebSocketManager()
    @State private var pinCode: String = ""
    @State private var showIpConfig = false
    @State private var showGuideSheet = false
    @Environment(\.scenePhase) private var scenePhase
    
    let connectivity = PhoneConnectivity.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark Gradient Background
                LinearGradient(
                    colors: [Color(hex: "08080C"), Color(hex: "10121A")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Glowing liquid ambient lights
                GeometryReader { geo in
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.blue.opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.45))
                            .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                            .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.2)
                        
                        Circle()
                            .fill(RadialGradient(colors: [Color.purple.opacity(0.15), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.45))
                            .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                            .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.2)
                        
                        Circle()
                            .fill(RadialGradient(colors: [Color(hex: "D07058").opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.35))
                            .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                            .offset(x: 0, y: -geo.size.height * 0.35)
                    }
                }
                .ignoresSafeArea()
                
                // Scrollable Main Content for Full Responsiveness across device sizes
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Top Fixed Interactive CLAW Pet Header
                        TopClaudePetHeader(connectionStatus: wsManager.connectionStatus)
                        
                        // Status Bar
                        connectionStatusBar
                        
                        if let error = wsManager.lastError {
                            errorBanner(error: error)
                        }
                        
                        if !wsManager.isPaired {
                            glassCard {
                                setupAndPairingView
                            }
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                if let request = wsManager.activeRequest {
                                    glassCard {
                                        activeRequestCard(request: request)
                                    }
                                } else {
                                    glassCard {
                                        emptyStateCard
                                    }
                                }
                                
                                glassCard {
                                    historySection
                                }
                                
                                glassCard {
                                    quickGuideCard
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable {
                    wsManager.disconnect()
                    wsManager.connect()
                }
            }
            .navigationTitle("CLAW Approve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showIpConfig = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "laptopcomputer.and.iphone")
                            Text("IP Config")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                if wsManager.isPaired {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { wsManager.resetPairing() }) {
                            Text("Unpair")
                                .foregroundColor(.red.opacity(0.8))
                                .font(.subheadline)
                        }
                    }
                }
            }
            .sheet(isPresented: $showIpConfig) {
                ipConfigSheet
            }
            .sheet(isPresented: $showGuideSheet) {
                connectionGuideFullSheet
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            wsManager.connect()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                wsManager.connect()
            }
        }
    }
    
    // MARK: - Connection Status Bar
    private var connectionStatusBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor, radius: 4)
                
                Text(wsManager.connectionStatus.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                
                Button(action: {
                    wsManager.disconnect()
                    wsManager.connect()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            
            Spacer()
            
            Button(action: { showIpConfig = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.caption2)
                    Text("Mac: \(wsManager.ipAddress)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        switch wsManager.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .authFailed: return .red
        }
    }
    
    // MARK: - Error Banner
    private func errorBanner(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
            Spacer()
            Button(action: { wsManager.connect() }) {
                Text("Retry")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.25), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Glass Card Wrapper (Strict Continuous Smooth Corners, No Square Edges)
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Setup & Pairing View (Simplified Connection Guide + PIN Input)
    private var setupAndPairingView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Connect to Mac Agent")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.top, 4)
            
            // Step-by-step instruction cards
            VStack(alignment: .leading, spacing: 10) {
                stepRow(number: "1", title: "Same Network", description: "Ensure iPhone and Mac are on the same Wi-Fi network.")
                stepRow(number: "2", title: "Start Mac CLI", description: "Run 'watchapprove' in your Mac Terminal.")
                stepRow(number: "3", title: "Enter PIN & IP", description: "Input your Mac's IP address and 6-digit pairing PIN below.")
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            // IP & PIN Entry
            VStack(spacing: 12) {
                HStack {
                    Text("Mac IP:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                    TextField("192.168.1.x", text: $wsManager.ipAddress)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                
                HStack(spacing: 12) {
                    Text("PIN Code:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                    
                    TextField("000000", text: $pinCode)
                        .keyboardType(.numberPad)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                
                Button(action: {
                    if pinCode.count == 6 {
                        wsManager.pair(pin: pinCode)
                    }
                }) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                        Text("Connect & Pair")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(pinCode.count == 6 ? Color.blue : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(pinCode.count != 6)
            }
            .padding(.top, 4)
        }
    }
    
    private func stepRow(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Color(hex: "D07058"))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Active Request Card
    private func activeRequestCard(request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    ClaudeMascotView()
                        .frame(width: 24, height: 16)
                    Text(request.agent)
                        .fontWeight(.bold)
                }
                .font(.headline)
                
                Spacer()
                
                riskBadge(risk: request.risk)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(request.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Dynamic Single-Line Option Buttons (Mirroring Agent's exact choices)
            VStack(spacing: 8) {
                ForEach(request.dynamicOptions) { opt in
                    Button(action: {
                        wsManager.sendDecision(requestId: request.id, action: opt.key)
                    }) {
                        HStack {
                            Text(opt.label)
                                .font(.system(size: 13, weight: opt.isPrimary ? .bold : .medium))
                                .foregroundColor(opt.isDestructive ? .red : (opt.isPrimary ? .white : .white.opacity(0.9)))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Image(systemName: opt.isDestructive ? "xmark.circle.fill" : (opt.isPrimary ? "checkmark.circle.fill" : "chevron.right.circle"))
                                .font(.system(size: 14))
                                .foregroundColor(opt.isDestructive ? .red : (opt.isPrimary ? .green : .white.opacity(0.5)))
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            opt.isPrimary ? Color.blue : (opt.isDestructive ? Color.red.opacity(0.15) : Color.white.opacity(0.08))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(opt.isDestructive ? Color.red.opacity(0.3) : (opt.isPrimary ? Color.blue.opacity(0.5) : Color.white.opacity(0.12)), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Command Code Block - placed BELOW the buttons
            VStack(alignment: .leading, spacing: 4) {
                Text("Requested Command:")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                
                Text(request.command)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
    }
    
    // MARK: - Empty State Card
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            switch wsManager.connectionStatus {
            case .connected:
                Text("CLAW Agent Connected & Listening")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Waiting for execution prompts from your Mac Agent Bridge...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
            case .connecting:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting to Mac...")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                }
                
                Text("Attempting connection to \(wsManager.ipAddress):\(wsManager.port)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
            case .disconnected, .authFailed:
                Text("Disconnected from Mac Agent")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.red.opacity(0.9))
                
                Text("Ensure 'watchapprove' is active on \(wsManager.ipAddress).")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Button(action: {
                    wsManager.disconnect()
                    wsManager.connect()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reconnect Now")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    // MARK: - Quick Guide Card
    private var quickGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                Text("Connection Info")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { showGuideSheet = true }) {
                    Text("Help Guide")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Text("Syncing automatically to paired Apple Watch via WatchConnectivity.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity History")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if !wsManager.history.isEmpty {
                    Text("\(wsManager.history.count) items")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            if wsManager.history.isEmpty {
                Text("No decisions made yet.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(wsManager.history.prefix(5)) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.command)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .lineLimit(1)
                                Text(item.agent)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            
                            Spacer()
                            
                            Text(item.action)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(item.action == "Approved" ? .green : (item.action == "Rejected" ? .red : .yellow))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    (item.action == "Approved" ? Color.green : (item.action == "Rejected" ? Color.red : Color.yellow))
                                        .opacity(0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - IP Config Sheet
    private var ipConfigSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Mac Connection Details")) {
                    HStack {
                        Text("Mac IP Address")
                        Spacer()
                        TextField("e.g. 192.168.1.4", text: $wsManager.ipAddress)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("8080", text: $wsManager.port)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.blue)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section(header: Text("Quick Setup Options")) {
                    Button("Use Localhost (Simulator)") {
                        wsManager.ipAddress = "127.0.0.1"
                    }
                    Button("Use Standard LAN IP (192.168.1.4)") {
                        wsManager.ipAddress = "192.168.1.4"
                    }
                }
                
                Section {
                    Button("Save & Reconnect") {
                        wsManager.disconnect()
                        wsManager.connect()
                        showIpConfig = false
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Connection Settings")
            .navigationBarItems(trailing: Button("Done") { showIpConfig = false })
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Full Connection Guide Sheet
    private var connectionGuideFullSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How CLAW Works")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Text("CLAW allows you to remotely review and approve shell commands requested by AI agents (Claude, Codex, etc.) from your iPhone or Apple Watch.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 1: Start Mac Agent")
                            .font(.headline)
                        Text("Open Terminal on your Mac and type:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("watchapprove")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 2: Connect Phone")
                            .font(.headline)
                        Text("Ensure both devices are on the same Wi-Fi network. Check the IP shown on your Mac terminal and input it in Connection Settings.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 3: Apple Watch Sync")
                            .font(.headline)
                        Text("Your Apple Watch will automatically receive approval requests whenever your iPhone is connected to the Mac Agent.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
            }
            .navigationTitle("Connection Guide")
            .navigationBarItems(trailing: Button("Close") { showGuideSheet = false })
        }
        .preferredColorScheme(.dark)
    }
    
    private func riskBadge(risk: String) -> some View {
        let color: Color
        let text: String
        switch risk.lowercased() {
        case "high":
            color = .red
            text = "High Risk"
        case "medium":
            color = .orange
            text = "Medium Risk"
        default:
            color = .green
            text = "Low Risk"
        }
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Top Fixed Interactive CLAW Pet Stage
struct TopClaudePetHeader: View {
    let connectionStatus: ConnectionStatus
    
    @State private var petOffset: CGFloat = 0
    @State private var isFacingLeft: Bool = false
    @State private var tilt: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var speechBubble: String? = "Tap me! 🐾"
    @State private var timerCount: Int = 0
    
    let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()
    
    private let speechOptions = [
        "CLAW Ready! 🤖",
        "Awaiting Prompts...",
        "Beep Boop! ⚡️",
        "Listening to Mac...",
        "Tap to Dance! 💃",
        "CLI Protected 🛡️"
    ]
    
    var body: some View {
        VStack(spacing: 6) {
            // Interactive Pet Playground Box
            ZStack {
                // Background Stage Card
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "D07058").opacity(0.4), .clear, Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 4) {
                        // Speech Bubble (If present)
                        if let text = speechBubble {
                            Text(text)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "D07058"))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "D07058").opacity(0.5), radius: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // CLAW Mascot
                        ClaudeMascotView()
                            .frame(width: 52, height: 34)
                            .shadow(color: Color(hex: "D07058").opacity(0.5), radius: 8)
                            .rotationEffect(.degrees(tilt))
                            .scaleEffect(x: (isFacingLeft ? -1 : 1) * scale, y: scale)
                            .offset(x: petOffset)
                            .onTapGesture {
                                triggerRandomAction()
                            }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .frame(height: 95)
            .padding(.horizontal)
            .onReceive(timer) { _ in
                timerCount += 1
                if timerCount % 2 == 0 {
                    triggerIdleWander()
                }
            }
        }
    }
    
    // Triggered on user tap!
    private func triggerRandomAction() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        let randomChoice = Int.random(in: 0...4)
        speechBubble = speechOptions.randomElement()
        
        switch randomChoice {
        case 0: // Jump Bounce
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                scale = 1.35
                tilt = -15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    scale = 1.0
                    tilt = 0
                }
            }
        case 1: // Spin & Flip
            withAnimation(.easeInOut(duration: 0.5)) {
                tilt = 360
                isFacingLeft.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                tilt = 0
            }
        case 2: // Side Wiggle Walk
            withAnimation(.easeInOut(duration: 0.4)) {
                petOffset = (petOffset > 0) ? -40 : 40
                isFacingLeft = petOffset < 0
                tilt = 12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation { tilt = 0 }
            }
        case 3: // Pulse Happy Shake
            withAnimation(.easeInOut(duration: 0.15).repeatCount(4, autoreverses: true)) {
                tilt = 10
                scale = 1.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                scale = 1.0
                tilt = 0
            }
        default: // Dance Step
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                petOffset = CGFloat.random(in: -50...50)
                isFacingLeft.toggle()
                scale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { scale = 1.0 }
            }
        }
        
        // Hide speech bubble after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                speechBubble = nil
            }
        }
    }
    
    // Automatic idle movement at top
    private func triggerIdleWander() {
        let newX = CGFloat.random(in: -60...60)
        isFacingLeft = newX < petOffset
        
        withAnimation(.easeInOut(duration: 2.0)) {
            petOffset = newX
        }
        
        withAnimation(.easeInOut(duration: 0.4).repeatCount(4, autoreverses: true)) {
            tilt = 6
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
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8 * 17) & 0xff, (int >> 4 & 0xf * 17) & 0xff, (int & 0xf * 17) & 0xff)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, (int >> 16) & 0xff, (int >> 8) & 0xff, (int & 0xff) & 0xff)
        case 8: // ARGB (32-bit)
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

// MARK: - Mecha Cat Mascot View
struct ClaudeMascotView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 12
            let h = geo.size.height / 10
            
            ZStack(alignment: .topLeading) {
                // Cybernetic Blue Armor Head & Collar (#1F4773)
                Group {
                    // Cat Ears (Pointed L & R)
                    Rectangle()
                        .fill(Color(hex: "18385A"))
                        .frame(width: w * 3, height: h * 3)
                        .offset(x: w * 1, y: 0)
                    
                    Rectangle()
                        .fill(Color(hex: "18385A"))
                        .frame(width: w * 3, height: h * 3)
                        .offset(x: w * 8, y: 0)
                    
                    // Head Helmet Base (Cols 2 to 9, Rows 2 to 7)
                    Rectangle()
                        .fill(Color(hex: "245486"))
                        .frame(width: w * 8, height: h * 6)
                        .offset(x: w * 2, y: h * 2)
                    
                    // Headphones / Side Antennas (Cols 0..1 and 10..11, Rows 3..5)
                    Rectangle()
                        .fill(Color(hex: "3472B2"))
                        .frame(width: w * 2, height: h * 3)
                        .offset(x: 0, y: h * 3)
                    
                    Rectangle()
                        .fill(Color(hex: "3472B2"))
                        .frame(width: w * 2, height: h * 3)
                        .offset(x: w * 10, y: h * 3)
                    
                    // Collar / Armor Base (Rows 8 to 9)
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
                        .shadow(color: Color(hex: "FF8800"), radius: 4)
                    
                    Rectangle()
                        .fill(Color(hex: "FF8800"))
                        .frame(width: w * 2, height: h * 1.5)
                        .offset(x: w * 6.5, y: h * 3.5)
                        .shadow(color: Color(hex: "FF8800"), radius: 4)
                }
            }
        }
    }
}
