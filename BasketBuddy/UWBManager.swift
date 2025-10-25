//
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

private struct PosePayload: Codable {
    let t: TimeInterval            // timestamp
    let distance: Double?          // in meters
    let direction: [Float]?        // unit vector in with coordinate (x,y,z)
    let position: [Float]?         // direction * distance (x,y,z) in meters (relative)
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

    private var session: NISession?
    private let serviceType = "basket-uwb"

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private var lastPoseSentAt: TimeInterval = 0
    private let poseSendInterval: TimeInterval = 0.2  // 5 Hz
    
    // peer token
    private var peerDiscoveryToken: NIDiscoveryToken?

    override init() {
        super.init()
        uwbLog.info("[\(ts())][\(myShortID)] UWBManager init")
        setupMultipeer()
    }

    func start() {
        uwbLog.info("[\(ts())][\(myShortID)] start() session? \(self.session == nil ? "no" : "yes")")
        if session == nil { createSession() }
        status = "Starting…"
        sendMyDiscoveryTokenIfPossible()
    }

    func stop() {
        session?.invalidate()
        session = nil
        status = "Stopped"
    }

    private func createSession() {
        uwbLog.info("[\(ts())][\(myShortID)] createSession()")

        let s = NISession()
        s.delegate = self
        session = s
        status = "Session created"
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

    private func sendMyDiscoveryTokenIfPossible() {
        guard let s = session, let token = s.discoveryToken else { createSession(); return }
        guard !mcSession.connectedPeers.isEmpty else { return }
        do {
            uwbLog.info("[\(ts())][\(myShortID)] attempt send token; sessionHasToken=\(self.session?.discoveryToken != nil) peers=\(self.mcSession.connectedPeers.map{$0.displayName}.joined(separator: ","))")

            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
            status = "Sent discovery token"
        } catch {
            status = "Send failed: \(error.localizedDescription)"
        }
    }

    private func handleReceivedPeerToken(_ data: Data) {
        do {
            uwbLog.info("[\(ts())][\(myShortID)] received peer token bytes=\(data.count)")

            let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
            peerDiscoveryToken = token
            status = "Got peer token — starting NI"
            startRangingIfPossible()
        } catch {
            status = "Failed to decode peer token: \(error.localizedDescription)"
        }
    }

    private func startRangingIfPossible() {
        guard let s = session else {
            createSession()
            startRangingIfPossible()
            return
        }
        guard let peer = peerDiscoveryToken else { return }
        let config = NINearbyPeerConfiguration(peerToken: peer)
        s.run(config)
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
    private func sendPoseUpdate(from obj: NINearbyObject, timestamp: TimeInterval) {
        guard !mcSession.connectedPeers.isEmpty else { return }

        let distanceD: Double? = obj.distance.map { Double($0) }
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
            position: posArr
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
        guard let obj = nearbyObjects.first else { return }

        if let d = obj.distance { self.lastDistance = Double(d) }
        if let dir = obj.direction { self.lastDirection = dir }
        self.isRangingLive = true
        self.status = "Ranging: \(String(format: "%.2f", self.lastDistance ?? -1)) m"

        let now = Date().timeIntervalSince1970
        if now - lastPoseSentAt >= poseSendInterval {
            lastPoseSentAt = now
            sendPoseUpdate(from: obj, timestamp: now)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        uwbLog.error("[\(ts())][\(myShortID)] NI invalidated error=\(error.localizedDescription, privacy: .public)")
        self.status = "Session invalidated: \(error.localizedDescription)"
        self.isRangingLive = false
        self.createSession()
        self.sendMyDiscoveryTokenIfPossible()
        self.startRangingIfPossible()
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
extension UWBManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
            switch state {
            case .connected:
                self.status = "Connected to \(peerID.displayName)"
                self.sendMyDiscoveryTokenIfPossible()
            case .connecting:
                self.status = "Connecting…"
            case .notConnected:
                self.status = "Disconnected"
                self.restartDiscovery()
            @unknown default: break
            }
        }

        func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
            if let pose = try? JSONDecoder().decode(PosePayload.self, from: data) {
                // Log position data
                let dist = pose.distance.map { String(format: "%.2f m", $0) } ?? "nil"
                let dir  = pose.direction.map { String(format: "[%.3f, %.3f, %.3f]", $0[0], $0[1], $0[2]) } ?? "nil"
                let pos: String
                if let p = pose.position {
                    pos = String(format: "[%.3f, %.3f, %.3f] m", p[0], p[1], p[2])
                } else {
                    pos = "nil"
                }
                print("📡 Position @\(pose.t): distance=\(dist) dir=\(dir) pos=\(pos) from \(peerID.displayName)")

                self.status = "Peer: d=\(dist) pos=\(pos)"
                return
            }

        handleReceivedPeerToken(data)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

@MainActor
extension UWBManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { }
}
