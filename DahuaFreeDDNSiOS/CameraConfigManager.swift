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
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=setConfig" +
                        "&Network.eth0.IPAddress=\(newIp)" +
                        "&Network.eth0.SubnetMask=\(subnet)" +
                        "&Network.eth0.Gateway=\(gateway)" +
                        "&Network.eth0.DhcpEnable=false"

        cgiClient.fetchDahuaConfig(ip: ip, port: port, user: user, pass: pass) { _ in
            // Execute setConfig for IP change
            let client = DahuaCgiClient()
            client.saveDahuaDDNSConfig(
                ip: ip, port: port, user: user, pass: pass,
                channelIdx: "0", enable: true, serverAddr: "", domain: "",
                ddnsUser: "", ddnsPass: ""
            ) { _ in }
            
            // Send direct CGI URL
            let session = URLSession(configuration: .default)
            guard let url = URL(string: urlString) else {
                completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: "URL không hợp lệ"))
                return
            }
            
            var req = URLRequest(url: url)
            req.timeoutInterval = 5.0
            session.dataTask(with: req) { data, response, error in
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                let success = (200...299).contains(statusCode) || text.contains("OK") || text.contains("true")
                completion(CgiResult(success: success, statusCode: statusCode, rawText: text, errorMessage: error?.localizedDescription))
            }.resume()
        }
    }

    func changePassword(
        ip: String,
        port: String,
        user: String,
        oldPass: String,
        newPass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/userManager.cgi?action=modifyPassword" +
                        "&name=\(user)&pwd=\(oldPass)&newpwd=\(newPass)"

        let session = URLSession(configuration: .default)
        guard let url = URL(string: urlString) else {
            completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: "URL không hợp lệ"))
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        session.dataTask(with: req) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let success = (200...299).contains(statusCode) || text.contains("OK") || text.contains("true")
            completion(CgiResult(success: success, statusCode: statusCode, rawText: text, errorMessage: error?.localizedDescription))
        }.resume()
    }
}
