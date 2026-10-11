import Foundation
import CoreLocation
import UIKit

struct LocationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let clManager = CLLocationManager()
    @Published var isLocating: Bool = false
    @Published var lastAddress: String = ""
    @Published var lastGoogleUrl: String = ""
    @Published var errorMessage: String? = nil

    private var completionHandler: ((Result<(address: String, url: String, lat: Double, lon: Double), LocationError>) -> Void)?

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Lấy vị trí GPS hiện tại, reverse geocode sang địa chỉ tiếng Việt và sinh link Google Maps
    func requestCurrentLocation(completion: @escaping (Result<(address: String, url: String, lat: Double, lon: Double), LocationError>) -> Void) {
        self.completionHandler = completion
        self.isLocating = true
        self.errorMessage = nil

        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = clManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            self.isLocating = false
            let err = "Ứng dụng chưa được cấp quyền vị trí. Vui lòng vào Cài đặt máy > Quyền riêng tư > Định vị để cho phép."
            self.errorMessage = err
            self.completionHandler?(.failure(LocationError(message: err)))
            self.completionHandler = nil
        case .authorizedWhenInUse, .authorizedAlways:
            clManager.requestLocation()
        @unknown default:
            clManager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        if isLocating {
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.isLocating = false
                let err = "Quyền định vị bị từ chối."
                self.errorMessage = err
                self.completionHandler?(.failure(LocationError(message: err)))
                self.completionHandler = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationManagerDidChangeAuthorization(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishWithError("Không lấy được tọa độ GPS.")
            return
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let mapsUrl = "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)"
        self.lastGoogleUrl = mapsUrl

        // Reverse Geocoding địa chỉ sang text
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLocating = false

                var addressComponents: [String] = []
                if let pm = placemarks?.first {
                    if let name = pm.name, !name.isEmpty {
                        addressComponents.append(name)
                    }
                    if let thoroughfare = pm.thoroughfare, !addressComponents.contains(thoroughfare) {
                        addressComponents.append(thoroughfare)
                    }
                    if let subLocality = pm.subLocality, !addressComponents.contains(subLocality) {
                        addressComponents.append(subLocality)
                    }
                    if let locality = pm.locality, !addressComponents.contains(locality) {
                        addressComponents.append(locality)
                    }
                    if let subAdmin = pm.subAdministrativeArea, !addressComponents.contains(subAdmin) {
                        addressComponents.append(subAdmin)
                    }
                    if let admin = pm.administrativeArea, !addressComponents.contains(admin) {
                        addressComponents.append(admin)
                    }
                }

                let finalAddress = addressComponents.isEmpty
                    ? String(format: "Tọa độ: %.5f, %.5f", lat, lon)
                    : addressComponents.joined(separator: ", ")

                self.lastAddress = finalAddress
                self.completionHandler?(.success((address: finalAddress, url: mapsUrl, lat: lat, lon: lon)))
                self.completionHandler = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishWithError("Lỗi lấy vị trí: \(error.localizedDescription)")
    }

    private func finishWithError(_ msg: String) {
        DispatchQueue.main.async {
            self.isLocating = false
            self.errorMessage = msg
            self.completionHandler?(.failure(LocationError(message: msg)))
            self.completionHandler = nil
        }
    }
}
