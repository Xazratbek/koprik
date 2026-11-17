import GameController
import KoprikKit
import Observation
import SwiftUI

/// Connected game controllers and what they send, for checking a pad before a game.
@MainActor
@Observable
final class ControllerMonitor {
    struct Pad: Identifiable {
        let id: ObjectIdentifier
        var name: String
        var kind: String
        var battery: Float?
        var charging = false
        var pressed: Set<String> = []
        var leftStick = CGPoint.zero
        var rightStick = CGPoint.zero
    }

    var pads: [Pad] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery()
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        GCController.stopWirelessControllerDiscovery()
    }

    private func refresh() {
        pads = GCController.controllers().map { controller in
            let id = ObjectIdentifier(controller)
            controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
                let snapshot = Self.read(gamepad)
                Task { @MainActor in self?.update(id, with: snapshot) }
            }
            return Pad(
                id: id,
                name: controller.vendorName ?? String(localized: "Controller"),
                kind: controller.productCategory,
                battery: controller.battery.map(\.batteryLevel),
                charging: controller.battery?.batteryState == .charging
            )
        }
    }

    private struct Snapshot: Sendable {
        var pressed: Set<String>
        var left: CGPoint
        var right: CGPoint
    }

    nonisolated private static func read(_ gamepad: GCExtendedGamepad) -> Snapshot {
        var pressed: Set<String> = []
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("A", gamepad.buttonA), ("B", gamepad.buttonB), ("X", gamepad.buttonX), ("Y", gamepad.buttonY),
            ("LB", gamepad.leftShoulder), ("RB", gamepad.rightShoulder), ("LT", gamepad.leftTrigger), ("RT", gamepad.rightTrigger),
            ("Menu", gamepad.buttonMenu), ("View", gamepad.buttonOptions), ("L3", gamepad.leftThumbstickButton),
            ("R3", gamepad.rightThumbstickButton), ("Up", gamepad.dpad.up), ("Down", gamepad.dpad.down),
            ("Left", gamepad.dpad.left), ("Right", gamepad.dpad.right),
        ]
        for (name, button) in buttons where button?.isPressed == true { pressed.insert(name) }
        return Snapshot(
            pressed: pressed,
            left: CGPoint(x: CGFloat(gamepad.leftThumbstick.xAxis.value), y: CGFloat(gamepad.leftThumbstick.yAxis.value)),
            right: CGPoint(x: CGFloat(gamepad.rightThumbstick.xAxis.value), y: CGFloat(gamepad.rightThumbstick.yAxis.value))
        )
    }

    private func update(_ id: ObjectIdentifier, with snapshot: Snapshot) {
        guard let index = pads.firstIndex(where: { $0.id == id }) else { return }
        pads[index].pressed = snapshot.pressed
        pads[index].leftStick = snapshot.left
        pads[index].rightStick = snapshot.right
    }
}

struct ControllersView: View {
    @State private var monitor = ControllerMonitor()

    var body: some View {
        Group {
            if monitor.pads.isEmpty {
                ContentUnavailableView(
                    "No controllers",
                    systemImage: "gamecontroller",
                    description: Text("Connect an Xbox, PlayStation or other controller by USB or in System Settings > Bluetooth. Games see it through Windows' XInput and DirectInput.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(monitor.pads) { pad in
                            PadCard(pad: pad)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .navigationTitle("Controllers")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

private struct PadCard: View {
    let pad: ControllerMonitor.Pad

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gamecontroller.fill").font(.title2)
                VStack(alignment: .leading) {
                    Text(verbatim: pad.name).font(.headline)
                    Text(verbatim: pad.kind).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let battery = pad.battery {
                    Label {
                        Text(battery, format: .percent.precision(.fractionLength(0)))
                    } icon: {
                        Image(systemName: pad.charging ? "battery.100.bolt" : "battery.75")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 24) {
                StickView(title: "Left stick", point: pad.leftStick)
                StickView(title: "Right stick", point: pad.rightStick)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pressed").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: pad.pressed.isEmpty ? "–" : pad.pressed.sorted().joined(separator: "  "))
                        .font(.title3.monospaced())
                        .contentTransition(.numericText())
                }
            }
            Text("Press buttons and move the sticks: what shows here is what Windows games receive.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

private struct StickView: View {
    let title: LocalizedStringKey
    let point: CGPoint

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 2)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: point.x * 30, y: -point.y * 30)
            }
            .frame(width: 74, height: 74)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
