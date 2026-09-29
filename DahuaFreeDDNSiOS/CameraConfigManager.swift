import Foundation

class CameraConfigManager {
    private let cgiClient = DahuaCgiClient()

    func changeIp(
        ip: String,
        port: String,
        user: String,
        pass: String,
        newIp: String,
        subnet: String = "255.255.255.0",
        gateway: String = "192.168.1.1",
        completion: @escaping (CgiResult) -> Void
    ) {
        cgiClient.changeCameraIp(
            currentIp: ip,
            newIp: newIp,
            subnetMask: subnet,
            gateway: gateway,
            user: user,
            pass: pass,
            completion: completion
        )
    }

    func changePassword(
        ip: String,
        port: String,
        user: String,
        oldPass: String,
        newPass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        cgiClient.changePassword(
            ip: ip,
            port: port,
            user: user,
            oldPass: oldPass,
            newPass: newPass,
            completion: completion
        )
    }
}
