import Foundation
import Observation

/// Source of location updates. A CoreLocation implementation arrives with the network transport
/// in Milestone 3; Milestone 1 ships `UnavailableLocationProvider`.
@MainActor
protocol LocationProviding: AnyObject {
    var isUpdating: Bool { get }
    func startUpdates()
    func stopUpdates()
}

@MainActor
final class UnavailableLocationProvider: LocationProviding {
    let isUpdating = false
    func startUpdates() {}
    func stopUpdates() {}
}

/// Enforces the location-sharing policy:
/// - off by default, opt-in per ride;
/// - only while a ride is active *and* the rider is in a group *and* a transport exists;
/// - stops immediately when the ride ends, the rider leaves the group, or opts out;
/// - the opt-in is cleared when the ride ends or the rider leaves.
@MainActor
@Observable
final class LocationSharingController {
    private(set) var optedIn = false
    private(set) var isRideActive = false
    private(set) var isInGroup = false
    private(set) var isSharing = false
    let transportAvailable: Bool

    @ObservationIgnored private let provider: any LocationProviding

    init(provider: any LocationProviding, transportAvailable: Bool) {
        self.provider = provider
        self.transportAvailable = transportAvailable
    }

    var unavailableReason: String? {
        transportAvailable ? nil : "Requires the network group transport (Milestone 3). The opt-in and shutdown rules are implemented and tested."
    }

    func setOptedIn(_ value: Bool) {
        optedIn = value && transportAvailable
        reconcile()
    }

    func rideDidStart() {
        isRideActive = true
        reconcile()
    }

    func rideDidEnd() {
        isRideActive = false
        optedIn = false
        reconcile()
    }

    func groupDidJoin() {
        isInGroup = true
        reconcile()
    }

    func groupDidLeave() {
        isInGroup = false
        optedIn = false
        reconcile()
    }

    private func reconcile() {
        let shouldShare = optedIn && isRideActive && isInGroup && transportAvailable
        if shouldShare, !provider.isUpdating {
            provider.startUpdates()
        } else if !shouldShare, provider.isUpdating {
            provider.stopUpdates()
        }
        isSharing = shouldShare && provider.isUpdating
    }
}
