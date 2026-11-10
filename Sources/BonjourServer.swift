// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation
import Network
import SystemConfiguration

/// Small TCP server that announces itself on the local network via Bonjour (mDNS).
/// Basis for Zwift (DirCon) and MyWhoosh (OpenBikeControl).
final class BonjourServer {
    let serviceType: String
    let preferredPort: UInt16?
    var name: String
    var txt: [String: String]

    var onClientsChanged: ((Int) -> Void)?
    var onData: ((NWConnection, [UInt8]) -> Void)?
    var onConnect: ((NWConnection) -> Void)?
    var log: ((String) -> Void)?

    private var listener: NWListener?
    private(set) var clients: [ObjectIdentifier: NWConnection] = [:]

    init(serviceType: String, name: String, txt: [String: String], preferredPort: UInt16? = nil) {
        self.serviceType = serviceType
        self.name = name
        self.txt = txt
        self.preferredPort = preferredPort
    }

    /// This Mac's Bonjour host name (e.g. "My-MacBook").
    static var localHostName: String {
        (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? Host.current().localizedName ?? "Mac"
    }

    func start() {
        #if SNAPSHOT
        return // preview renderer: never announce a second "Shifty" on the network
        #endif
        stop()
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        params.allowLocalEndpointReuse = true
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        do {
            if let p = preferredPort, let port = NWEndpoint.Port(rawValue: p),
               let l = try? NWListener(using: params, on: port) {
                listener = l
            } else {
                listener = try NWListener(using: params)
            }
        } catch {
            log?("\(serviceType) could not start: \(error.localizedDescription)")
            return
        }
        guard let listener else { return }
        listener.service = NWListener.Service(name: name, type: serviceType, domain: nil,
                                              txtRecord: NWTXTRecord(txt))
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log?("\(self.serviceType) ready on port \(listener.port?.rawValue ?? 0) as \"\(self.name)\"")
            case .failed(let e):
                self.log?("\(self.serviceType) error: \(e)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for c in clients.values { c.cancel() }
        clients.removeAll()
        onClientsChanged?(0)
    }

    func send(_ bytes: [UInt8], to conn: NWConnection? = nil) {
        let targets = conn.map { [$0] } ?? Array(clients.values)
        for c in targets {
            c.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }
    }

    private func accept(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        clients[key] = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log?("\(self.serviceType): client connected \(conn.endpoint)")
                self.onClientsChanged?(self.clients.count)
                self.onConnect?(conn)
            case .failed, .cancelled:
                if self.clients.removeValue(forKey: key) != nil {
                    self.log?("\(self.serviceType): client disconnected")
                    self.onClientsChanged?(self.clients.count)
                }
            default: break
            }
        }
        conn.start(queue: .main)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.onData?(conn, [UInt8](data)) }
            if done || error != nil {
                conn.cancel()
                return
            }
            self.receive(conn)
        }
    }
}
