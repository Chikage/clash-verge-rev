import Foundation
import NetworkExtension
import OSLog

final class PacketBridge: @unchecked Sendable {
    private let flow: NEPacketTunnelFlow
    private let queue = DispatchQueue(label: "io.github.clash-verge-rev.packets")
    private var stopped = false

    init(flow: NEPacketTunnelFlow) { self.flow = flow }

    func beginReading() {
        flow.readPackets { [weak self] packets, families in
            guard let self else { return }
            self.queue.async {
                guard !self.stopped else { return }
                for (packet, family) in zip(packets, families) {
                    var bytes = [UInt8](packet)
                    bytes.withUnsafeMutableBufferPointer {
                        _ = SwihomoCoreInputPacket($0.baseAddress, $0.count, family.int32Value)
                    }
                }
                self.beginReading()
            }
        }
    }

    func deliver(_ packet: Data, family: Int32) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.flow.writePackets([packet], withProtocols: [NSNumber(value: family)])
        }
    }

    func stop() { queue.sync { stopped = true } }
}

final class PacketDestination: @unchecked Sendable {
    static let shared = PacketDestination()
    private let lock = NSLock()
    private var bridge: PacketBridge?

    func install(_ bridge: PacketBridge?) {
        lock.lock()
        self.bridge = bridge
        lock.unlock()
    }

    func deliver(_ packet: Data, family: Int32) {
        lock.lock()
        let destination = bridge
        lock.unlock()
        destination?.deliver(packet, family: family)
    }
}

@_cdecl("swihomo_write_packet")
func writeCorePacket(_ bytes: UnsafePointer<UInt8>?, _ count: Int, _ family: Int32) {
    guard let bytes, count > 0 else { return }
    PacketDestination.shared.deliver(Data(bytes: bytes, count: count), family: family)
}

@_cdecl("swihomo_write_log")
func writeCoreLog(_ level: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?) {
    guard let message else { return }
    Logger(subsystem: "io.github.clash-verge-rev.ios", category: "Mihomo")
        .debug("\(String(cString: message), privacy: .private)")
}
