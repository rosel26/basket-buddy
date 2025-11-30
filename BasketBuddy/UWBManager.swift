//  UWBManager.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-10-04.
//

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine
import UIKit
import OSLog
import ARKit
import Network

private var udpConn: NWConnection?

enum FollowingRole: String, Codable {
    case shopper
    case cartLeft
    case cartRight
}

func setupUDP() {
    if udpConn != nil { return }
    // let host = NWEndpoint.Host("172.20.10.8")
    let host = NWEndpoint.Host("172.26.94.205")

    let port = NWEndpoint.Port("5555")!
    let conn = NWConnection(host: host, port: port, using: .udp)
    conn.start(queue: .global())
    udpConn = conn
}

private struct PosePayload: Codable {
    let t: TimeInterval
    let distance: Double?
    let direction: [Float]?
    let position: [Float]?
    let deviceId: String?
}

private let uwbLog = Logger(subsystem: "com.basketbuddy.app", category: "UWB")

private func ts() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withTime, .withFractionalSeconds]
    return f.string(from: Date())
}

private let myShortID: String = {
    let cleaned = UIDevice.current.name
        .replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
    return String(cleaned.prefix(8)).uppercased()
}()

@MainActor
final class UWBManager: NSObject, ObservableObject {

    @Published var status: String = "Idle"
    @Published var lastDistance: Double?
    @Published var lastDirection: SIMD3<Float>?
    @Published var isRangingLive = false
    @Published var isReady = false
    
    @Published var role: FollowingRole = .shopper

    private var session: NISession?
    private let arSession = ARSession()
    private var arSessionRunning = false
    private var hasAttachedAR = false
    private var isRunningNI = false
    private var isARInitializing = false
    private var arTrackingIsGood = false  // if AR has good tracking

    private let serviceType = "basket-uwb"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var mcSession: MCSession!
    
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private var lastPoseSentAt: TimeInterval = 0
    private let poseSendInterval: TimeInterval = 0.2 // 5 Hz

    private var peerDiscoveryToken: NIDiscoveryToken?
    private var lastPeerTokenBlob: Data?

    private var niRestartWorkItem: DispatchWorkItem?
    
//    private var lastUpdateTimestamp: TimeInterval = 0
//    private var updateCount: Int = 0
//    private var lastRatePrint: TimeInterval = 0

    override init() {
        super.init()
        uwbLog.info("[\(ts())][\(myShortID)] UWBManager init")
        arSession.delegate = self
        
        createSession()
        setupMultipeer()
    }
    
    func start() {
        uwbLog.info("[\(ts())][\(myShortID)] start() session? \(self.session == nil ? "no" : "yes")")
        if session == nil { createSession() }
        status = "Starting…"
        
        if #available(iOS 16.0, *) {
            ensureARSessionRunning()
        }
        
        sendMyDiscoveryTokenIfPossible()
    }

    func stop() {
        session?.invalidate()
        session = nil
        hasAttachedAR = false
        isRunningNI = false

        if arSessionRunning {
            arSession.pause()
            arSessionRunning = false
        }

        status = "Stopped"
    }

    private func createSession() {
        uwbLog.info("[\(ts())][\(myShortID)] createSession()")
        let s = NISession()
        s.delegate = self
        session = s
        isRunningNI = false
        status = "Session created"
        
        if #available(iOS 16.0, *) {
            s.setARSession(arSession)
            hasAttachedAR = true
        }
    }

    private func setupMultipeer() {
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        uwbLog.info("[\(ts())][\(myShortID)] MC setup: advertising + browsing")

        status = "Advertising & browsing"
    }
    
    private func ensureARSessionRunning() {
        guard !arSessionRunning && !isARInitializing else { return }

        isARInitializing = true
        arTrackingIsGood = false
        uwbLog.info("[\(ts())][\(myShortID)] Starting AR session...")

        let config = ARWorldTrackingConfiguration()
        
        config.worldAlignment = .gravity
        config.isCollaborationEnabled = false
        config.initialWorldMap = nil
        
        if #available(iOS 16.0, *) {
            config.frameSemantics = []
        }

        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        arSessionRunning = true
        isARInitializing = false
        uwbLog.info("[\(ts())][\(myShortID)] AR session started, waiting for good tracking...")
    }

    private func sendMyDiscoveryTokenIfPossible() {
        guard let s = session, let token = s.discoveryToken else {
            uwbLog.info("[\(ts())][\(myShortID)] No token to send yet")
            return
        }
        guard !mcSession.connectedPeers.isEmpty else {
            uwbLog.info("[\(ts())][\(myShortID)] No connected peers to send token to")
            return
        }
        do {
            let peerNames = mcSession.connectedPeers.map { $0.displayName }.joined(separator: ",")
            uwbLog.info("[\(ts())][\(myShortID)] Sending token to peers: \(peerNames)")
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
            self.status = "Sent discovery token to \(peerNames)"
            uwbLog.info("[\(ts())][\(myShortID)] Token sent successfully (\(data.count) bytes)")
        } catch {
            uwbLog.error("[\(ts())][\(myShortID)] Token send failed: \(error.localizedDescription)")
            self.status = "Send failed: \(error.localizedDescription)"
        }
    }

    private func handleReceivedPeerToken(_ data: Data) {
        Task { @MainActor in
            if data == lastPeerTokenBlob { return }
            
            do {
                uwbLog.info("[\(ts())][\(myShortID)] received peer token bytes=\(data.count)")
                let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
                
                if let myToken = session?.discoveryToken {
                    let myData = try? NSKeyedArchiver.archivedData(withRootObject: myToken, requiringSecureCoding: true)
                    if myData == data {
                        uwbLog.warning("[\(ts())][\(myShortID)] Received own token")
                        status = "Can't range with self"
                        return
                    }
                }
                
                lastPeerTokenBlob = data
                peerDiscoveryToken = token
                status = "Got peer token — waiting for AR"
                uwbLog.info("[\(ts())][\(myShortID)] Peer token accepted, will start ranging")
                
                if #available(iOS 16.0, *) {
                    if !arSessionRunning && !isARInitializing {
                        ensureARSessionRunning()
                    } else if arSessionRunning {
                        startRangingIfPossible()
                    }
                } else {
                    startRangingIfPossible()
                }
            } catch {
                status = "Failed to decode peer token: \(error.localizedDescription)"
            }
        }
    }

    private func startRangingIfPossible() {
        guard let s = session else {
            createSession()
            return
        }
        guard let peer = peerDiscoveryToken else { return }
        guard !isRunningNI else { return }

        if #available(iOS 16.0, *) {
            guard arSessionRunning else {
                uwbLog.info("[\(ts())][\(myShortID)] Waiting for AR session to start...")
                return
            }
            
            guard arTrackingIsGood else {
                uwbLog.info("[\(ts())][\(myShortID)] Waiting for AR tracking to be good...")
                return
            }
            
            if !hasAttachedAR {
                s.setARSession(arSession)
                hasAttachedAR = true
                uwbLog.info("[\(ts())][\(myShortID)] attached ARSession to NISession")
            }
        }

        let cfg = NINearbyPeerConfiguration(peerToken: peer)
        if #available(iOS 16.0, *) {
            cfg.isCameraAssistanceEnabled = true
        }

        s.run(cfg)
        isRunningNI = true
        uwbLog.info("[\(ts())][\(myShortID)] running NI with peer token")
        status = "Ranging…"
    }

    private func restartDiscovery() {
        uwbLog.info("[\(ts())][\(myShortID)] restartDiscovery() stop→start")

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            self.status = "Restarted discovery"
        }
    }
    
    func sendPoseToComputer(distance: Double, position: [Float]?) {
        guard role == .cartLeft || role == .cartRight else {
            return
        }
        
        setupUDP()
        
        let now = Date().timeIntervalSince1970
        
        var frame: [String: Any] = [
            "t": now,
            "deviceId": myShortID,
            "distance": distance,
            "position": position as Any,
            "role": role.rawValue
        ]
        
        let data = try! JSONSerialization.data(withJSONObject: frame)
        udpConn?.send(content: data + Data([0x0A]), completion: .contentProcessed { _ in })
    }

    private func sendPoseUpdate(from obj: NINearbyObject, timestamp: TimeInterval) {
        guard !mcSession.connectedPeers.isEmpty else { return }

        let distanceD: Double? = obj.distance.map(Double.init)
        let dirArr: [Float]? = obj.direction.map { [$0.x, $0.y, $0.z] }

        var posArr: [Float]? = nil
        if let d = obj.distance, let dir = obj.direction {
            let pos = dir * d
            posArr = [pos.x, pos.y, pos.z]
        }

        let payload = PosePayload(
            t: timestamp,
            distance: distanceD,
            direction: dirArr,
            position: posArr,
            deviceId: myShortID
        )

        do {
            let data = try JSONEncoder().encode(payload)
            try mcSession.send(data, toPeers: mcSession.connectedPeers, with: .unreliable)
        } catch {
            self.status = "Pose send failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
extension UWBManager: NISessionDelegate {

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        
        // Getting data stream rate
        
//        let now1 = CACurrentMediaTime()
//
//        if lastUpdateTimestamp == 0 {
//            lastUpdateTimestamp = now1
//            lastRatePrint = now1
//        } else {
//            updateCount += 1
//            
//            let dt = now1 - lastUpdateTimestamp
//            let instRate = 1.0 / dt
//            print(String(format: "NI Instant rate: %.1f Hz (dt=%.4f)", instRate, dt))
//            lastUpdateTimestamp = now1
//        }
//
//        if now1 - lastRatePrint >= 1.0 {
//            print("NI avg rate over past second: \(updateCount) Hz")
//            updateCount = 0
//            lastRatePrint = now1
//        }
        
        guard let obj = nearbyObjects.first else { return }

        let now = Date().timeIntervalSince1970
        if let d = obj.distance { self.lastDistance = Double(d) }
        if let dir = obj.direction {
            self.lastDirection = dir
            print("Direction from didUpdate \(obj.horizontalAngle)")
        }

        self.isRangingLive = true
        
        let distStr = String(format: "%.2f", self.lastDistance ?? -1)
        self.status = "Ranging: \(distStr) m"

        if now - lastPoseSentAt >= poseSendInterval {
            lastPoseSentAt = now
            sendPoseUpdate(from: obj, timestamp: now)
        }
    }

    @available(iOS 16.0, *)
    func sessionRequiresCameraAssistance(_ session: NISession) {
        uwbLog.info("[\(ts())][\(myShortID)] sessionRequiresCameraAssistance called")
        ensureARSessionRunning()
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        uwbLog.error("[\(ts())][\(myShortID)] NI invalidated error=\(error.localizedDescription, privacy: .public)")
        self.status = "Session invalidated: \(error.localizedDescription)"
        self.isRangingLive = false

        self.isRunningNI = false
        self.hasAttachedAR = false

        niRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.createSession()
                self.sendMyDiscoveryTokenIfPossible()
                self.startRangingIfPossible()
            }
        }
        niRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func sessionWasSuspended(_ session: NISession) {
        uwbLog.info("[\(ts())][\(myShortID)] NI suspended")
        self.status = "Session suspended"
    }

    func sessionSuspensionEnded(_ session: NISession) {
        uwbLog.info("[\(ts())][\(myShortID)] NI suspension ended — rerun")
        self.status = "Session resumed"
        self.startRangingIfPossible()
    }
}

@MainActor
extension UWBManager: ARSessionDelegate {
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .notAvailable:
            uwbLog.info("[\(ts())][\(myShortID)] AR tracking: notAvailable")
            arTrackingIsGood = false
        case .limited(let reason):
            uwbLog.info("[\(ts())][\(myShortID)] AR tracking: limited \(String(describing: reason))")
        case .normal:
            uwbLog.info("[\(ts())][\(myShortID)] AR tracking: normal")
            arTrackingIsGood = true
            startRangingIfPossible()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        uwbLog.error("[\(ts())][\(myShortID)] ARSession failed: \(error.localizedDescription, privacy: .public)")
        arSessionRunning = false
        isARInitializing = false
        arTrackingIsGood = false
    }
}

extension UWBManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let peerName = peerID.displayName
            switch state {
            case .connected:
                uwbLog.info("[\(ts())][\(myShortID)] MC connected to: \(peerName)")
                self.status = "Connected to \(peerName)"
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.sendMyDiscoveryTokenIfPossible()
            case .connecting:
                uwbLog.info("[\(ts())][\(myShortID)] MC connecting to: \(peerName)")
                self.status = "Connecting to \(peerName)…"
            case .notConnected:
                uwbLog.info("[\(ts())][\(myShortID)] MC disconnected from: \(peerName)")
                self.status = "Disconnected from \(peerName)"
                self.restartDiscovery()
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let pose = try? JSONDecoder().decode(PosePayload.self, from: data) {
            let dist = pose.distance.map { String(format: "%.2f m", $0) } ?? "nil"
            let dir  = pose.direction.map { String(format: "[%.3f, %.3f, %.3f]", $0[0], $0[1], $0[2]) } ?? "nil"
            
            Task { @MainActor in
                self.sendPoseToComputer(
                    distance: pose.distance ?? -1,
                    position: pose.position
                )

                let dist = pose.distance.map { String(format: "%.2f m", $0) } ?? "nil"
                let dir  = pose.direction.map { "[\($0[0]),\($0[1]),\($0[2])]" } ?? "nil"
                let pos  = pose.position.map { "[\($0[0]),\($0[1]),\($0[2])]" } ?? "nil"

                print("""
                Position @\(pose.t):
                    distance=\(dist) dir=\(dir) pos=\(pos)
                """)

                self.status = "Peer: d=\(dist) pos=\(pos)"
            }
            return
        }

        Task { @MainActor in
            self.handleReceivedPeerToken(data)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension UWBManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            invitationHandler(true, self.mcSession)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            if self.mcSession.connectedPeers.contains(peerID) {
                uwbLog.info("[\(ts())][\(myShortID)] Already connected to: \(peerID.displayName)")
                return
            }
            
            uwbLog.info("[\(ts())][\(myShortID)] Found peer: \(peerID.displayName), inviting...")
            browser.invitePeer(peerID, to: self.mcSession, withContext: nil, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { }
}
