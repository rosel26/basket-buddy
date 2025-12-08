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
import Network

private var udpConn: NWConnection?

enum FollowingRole: String, Codable {
    case shopper
    case cartLeft
    case cartRight
}

func setupUDP() {
    if udpConn != nil { return }
    let host = NWEndpoint.Host("172.20.10.8")

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
    let role: FollowingRole?
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

    private let serviceType = "basket-uwb"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var mcSession: MCSession!
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var lastPoseSentAt: TimeInterval = 0
    private let poseSendInterval: TimeInterval = 0.2 // 5 Hz
    
    // Multi-peer NI
    private var niSessions: [MCPeerID: NISession] = [:]
    private var peerTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var peerForSession: [ObjectIdentifier: MCPeerID] = [:]
    
    private var peerRoles: [MCPeerID: FollowingRole] = [:]


    private var niRestartWorkItem: DispatchWorkItem?
    
    override init() {
        super.init()
        uwbLog.info("[\(ts())][\(myShortID)] UWBManager init")

    }
    
    func sendMyRoleToPeers() {
        guard !mcSession.connectedPeers.isEmpty else { return }
        let payload = ["role": role.rawValue]

        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
            uwbLog.info("[\(ts())][\(myShortID)] Sent my role \(self.role.rawValue) to peers")
        }
    }
    
    
    func startForCurrentRole() {
        if isReady {
            uwbLog.info("[\(ts())][\(myShortID)] startForCurrentRole() called but already ready")
            return
        }

        uwbLog.info("[\(ts())][\(myShortID)] Starting for role \(self.role.rawValue)")
        
        setupMultipeer()
        
        isReady = true
    }
    
    func start() {
        uwbLog.info("[\(ts())][\(myShortID)] start() called")
        status = "Starting…"
        
    }

    func stop() {
        for (_, s) in niSessions {
                s.invalidate()
            }
        niSessions.removeAll()
        peerForSession.removeAll()
        peerTokens.removeAll()

        status = "Stopped"
    }
    
    @MainActor
    private func setupNISessionForPeerIfNeeded(_ peerID: MCPeerID) {
        if niSessions[peerID] != nil {
            return // already set up
        }

        let session = NISession()
        session.delegate = self

        niSessions[peerID] = session
        peerForSession[ObjectIdentifier(session)] = peerID

        guard let token = session.discoveryToken else {
            uwbLog.error("[\(ts())][\(myShortID)] No discoveryToken for peer \(peerID.displayName)")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            try mcSession.send(data, toPeers: [peerID], with: .reliable)
            uwbLog.info("[\(ts())][\(myShortID)] Sent discovery token to \(peerID.displayName)")
        } catch {
            uwbLog.error("[\(ts())][\(myShortID)] Failed to send token to \(peerID.displayName): \(error.localizedDescription)")
        }
    }
    
    private func setupMultipeer() {
            mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            mcSession.delegate = self

            let discoveryInfo = ["role": role.rawValue]

            let adv = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                   discoveryInfo: discoveryInfo,
                                                   serviceType: serviceType)
            adv.delegate = self
            adv.startAdvertisingPeer()
            self.advertiser = adv
        
            switch role {
            case .shopper:
                // Shopper advertises and browses
                let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
                br.delegate = self
                br.startBrowsingForPeers()
                self.browser = br

                uwbLog.info("[\(ts())][\(myShortID)] MC setup (shopper): advertising + browsing")
                status = "Advertising & browsing"

            case .cartLeft, .cartRight:
                // Carts only advertise
                browser = nil
                uwbLog.info("[\(ts())][\(myShortID)] MC setup (cart): advertising only")
                status = "Advertising"
            }
        }

    @MainActor
    private func handleReceivedPeerToken(_ data: Data, from peerID: MCPeerID) {
        
        if role == .cartLeft || role == .cartRight {
                if let remoteRole = peerRoles[peerID] {
                    // We know their role
                    print(remoteRole)
                    guard remoteRole == .shopper else {
                        uwbLog.info("[\(ts())][\(myShortID)] Ignoring token from non-shopper \(peerID.displayName) (role=\(remoteRole.rawValue))")
                        return
                    }
                } else {
                    uwbLog.info("[\(ts())][\(myShortID)] No known role for \(peerID.displayName) yet, accepting token for now")
                }
            }
        

        do {
            uwbLog.info("[\(ts())][\(myShortID)] received peer token bytes=\(data.count) from \(peerID.displayName)")

            guard let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: data
            ) else {
                uwbLog.error("[\(ts())][\(myShortID)] Failed to decode NIDiscoveryToken from \(peerID.displayName)")
                return
            }

            for (_, mySession) in niSessions {
                if let myToken = mySession.discoveryToken {
                    let myData = try? NSKeyedArchiver.archivedData(
                        withRootObject: myToken,
                        requiringSecureCoding: true
                    )
                    if myData == data {
                        uwbLog.warning("[\(ts())][\(myShortID)] Received our own token back from \(peerID.displayName)")
                        status = "Can't range with self"
                        return
                    }
                }
            }

            // Store this peer's token
            peerTokens[peerID] = token

            uwbLog.info("[\(ts())][\(myShortID)] Peer token accepted from \(peerID.displayName), starting ranging")
            status = "Got peer token from \(peerID.displayName)"

            // Start or restart a dedicated session for this peer
            startRanging(with: peerID, token: token)

        } catch {
            status = "Failed to decode peer token: \(error.localizedDescription)"
            uwbLog.error("[\(ts())][\(myShortID)] Failed to decode peer token: \(error.localizedDescription)")
        }
    }


    @MainActor
    private func startRanging(with peerID: MCPeerID, token: NIDiscoveryToken) {
        
        guard let session = niSessions[peerID] else {
               uwbLog.error("[\(ts())][\(myShortID)] No NISession for peer \(peerID.displayName) when starting ranging")
               return
        }

        let cfg = NINearbyPeerConfiguration(peerToken: token)
        session.run(cfg)

        uwbLog.info("[\(ts())][\(myShortID)] Running NI with peer \(peerID.displayName)")
        status = "Ranging with \(peerID.displayName)…"
    }

    private func restartDiscovery() {
        uwbLog.info("[\(ts())][\(myShortID)] restartDiscovery() stop→start")
        guard advertiser != nil else {
            uwbLog.warning("[\(ts())][\(myShortID)] restartDiscovery() called but advertiser is nil; re-running setupMultipeer()")
            setupMultipeer()
            return
        }

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)

            self.advertiser?.startAdvertisingPeer()
            self.browser?.startBrowsingForPeers()
            self.status = "Restarted discovery"
        }
    }
    
    func sendPoseToComputer(distance: Double) {
        guard role == .cartLeft || role == .cartRight else {
            return
        }
        
        setupUDP()
        
        let now = Date().timeIntervalSince1970
        
        var frame: [String: Any] = [
            "t": now,
            "deviceId": myShortID,
            "distance": distance,
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
            deviceId: myShortID,
            role: role
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
        
        guard let obj = nearbyObjects.first,
                      let dist = obj.distance else { return }

        // Figure out which peer this session belongs to
        let key = ObjectIdentifier(session)
        let peerID = peerForSession[key]
        let now = Date().timeIntervalSince1970
                
        let remoteRole = peerID.flatMap { peerRoles[$0] } ?? .shopper

        let roleLabel: String
            switch remoteRole {
            case .cartLeft:  roleLabel = "LEFT"
            case .cartRight: roleLabel = "RIGHT"
            case .shopper:   roleLabel = "SHOPPER"
        }

        // Update UI-ish state
        self.lastDistance = Double(dist)
        self.isRangingLive = true
        let distStr = String(format: "%.2f", dist)
        self.status = "Ranging: \(distStr) m"

        print("""
                Position @\(now):
                    distance=\(distStr) from \(roleLabel)
                """)
        
        self.sendPoseToComputer(distance: Double(dist))
        
        self.isRangingLive = true

        self.status = "Ranging: \(distStr) m"

        if now - lastPoseSentAt >= poseSendInterval {
            lastPoseSentAt = now
            sendPoseUpdate(from: obj, timestamp: now)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        uwbLog.error("[\(ts())][\(myShortID)] NI invalidated error=\(error.localizedDescription, privacy: .public)")
        self.status = "Session invalidated: \(error.localizedDescription)"
        self.isRangingLive = false

        let key = ObjectIdentifier(session)
        if let peerID = peerForSession[key] {
            uwbLog.info("[\(ts())][\(myShortID)] Cleaning up NI session for peer \(peerID.displayName)")
            niSessions[peerID] = nil
            peerForSession[key] = nil

            if let token = peerTokens[peerID] {
                uwbLog.info("[\(ts())][\(myShortID)] Restarting NI for peer \(peerID.displayName)")
                startRanging(with: peerID, token: token)
            }
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        uwbLog.info("[\(ts())][\(myShortID)] NI suspended")
        self.status = "Session suspended"
    }

    func sessionSuspensionEnded(_ session: NISession) {
        uwbLog.info("[\(ts())][\(myShortID)] NI suspension ended — rerun")
        self.status = "Session resumed"

        let key = ObjectIdentifier(session)
        if let peerID = peerForSession[key],
           let token = peerTokens[peerID] {
            startRanging(with: peerID, token: token)
        }
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
                self.setupNISessionForPeerIfNeeded(peerID)
                self.sendMyRoleToPeers()

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

        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let roleStr = dict["role"] as? String,
           let role = FollowingRole(rawValue: roleStr) {

            Task { @MainActor in
                peerRoles[peerID] = role
            }
            return
        }

        Task { @MainActor in
            self.handleReceivedPeerToken(data, from: peerID)
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
