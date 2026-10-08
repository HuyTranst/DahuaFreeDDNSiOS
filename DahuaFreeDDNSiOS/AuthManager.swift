import Foundation
import CryptoKit

/// Hệ thống quản lý tài khoản & phân quyền bản quyền (Google Apps Script / Sheet Backend)
public class AuthManager: ObservableObject {
    public static let shared = AuthManager()
    
    // Server URL Google Apps Script cố định trong nền (Ẩn hoàn toàn khỏi giao diện người dùng)
    public let defaultServerUrl = "https://script.google.com/macros/s/AKfycbzOWTr3LLzTb33Ky7OMK8KbTBeoWEWXliea-7gO227YN076Pnu-F5TWEAOuvFwU-TFb/exec"
    
    @Published public var isLoggedIn: Bool = false
    @Published public var username: String = ""
    @Published public var role: String = "FREE" // "PRO", "FREE", "ADMIN"
    @Published public var expireDate: String = "2099-12-31"
    @Published public var points: Int = 0
    @Published public var lastCheckTimestamp: Double = 0
    
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    
    private let keyUsername = "KEY_AUTH_USERNAME"
    private let keyRole = "KEY_AUTH_ROLE"
    private let keyExpire = "KEY_AUTH_EXPIRE"
    private let keyPoints = "KEY_AUTH_POINTS"
    private let keyLastCheck = "KEY_AUTH_LAST_CHECK"
    private let keyIsLoggedIn = "KEY_AUTH_IS_LOGGED_IN"
    
    public init() {
        loadSession()
        // Tự động kiểm tra lại bản quyền nếu đã quá 5 ngày
        if isLoggedIn && isNeedRecheckServer() {
            checkStatus(silent: true)
        }
    }
    
    public func loadSession() {
        let def = UserDefaults.standard
        self.isLoggedIn = def.bool(forKey: keyIsLoggedIn)
        self.username = def.string(forKey: keyUsername) ?? ""
        self.role = def.string(forKey: keyRole) ?? "FREE"
        self.expireDate = def.string(forKey: keyExpire) ?? "2099-12-31"
        self.points = def.integer(forKey: keyPoints)
        self.lastCheckTimestamp = def.double(forKey: keyLastCheck)
    }
    
    public func saveSession(username: String, role: String, expireDate: String, points: Int) {
        let def = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        def.set(true, forKey: keyIsLoggedIn)
        def.set(username, forKey: keyUsername)
        def.set(role, forKey: keyRole)
        def.set(expireDate, forKey: keyExpire)
        def.set(points, forKey: keyPoints)
        def.set(now, forKey: keyLastCheck)
        
        DispatchQueue.main.async {
            self.isLoggedIn = true
            self.username = username
            self.role = role
            self.expireDate = expireDate
            self.points = points
            self.lastCheckTimestamp = now
        }
    }
    
    /// Kiểm tra xem phiên đăng nhập đã quá 5 ngày kể từ lần xác thực gần nhất hay chưa
    public func isNeedRecheckServer() -> Bool {
        let now = Date().timeIntervalSince1970
        let fiveDaysSeconds: Double = 5 * 24 * 3600
        return (now - lastCheckTimestamp) >= fiveDaysSeconds
    }
    
    /// Số ngày còn lại trước lần kiểm tra máy chủ tiếp theo
    public func getDaysUntilNextCheck() -> Int {
        let fiveDaysSeconds: Double = 5 * 24 * 3600
        let nextCheck = lastCheckTimestamp + fiveDaysSeconds
        let diff = nextCheck - Date().timeIntervalSince1970
        if diff <= 0 { return 0 }
        return Int(ceil(diff / (24 * 3600)))
    }
    
    public func logout() {
        let def = UserDefaults.standard
        def.removeObject(forKey: keyIsLoggedIn)
        def.removeObject(forKey: keyUsername)
        def.removeObject(forKey: keyRole)
        def.removeObject(forKey: keyExpire)
        def.removeObject(forKey: keyPoints)
        def.removeObject(forKey: keyLastCheck)
        
        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.username = ""
            self.role = "FREE"
            self.expireDate = "2099-12-31"
            self.points = 0
            self.lastCheckTimestamp = 0
            self.errorMessage = nil
            self.successMessage = "Đã đăng xuất tài khoản thành công."
        }
    }
    
    /// Băm mật khẩu theo chuẩn SHA-256 an toàn
    public static func hashPassword(_ pass: String) -> String {
        let data = Data(pass.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Đăng nhập tài khoản
    public func login(user: String, pass: String, completion: ((Bool, String) -> Void)? = nil) {
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pass.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty || p.isEmpty {
            let msg = "Vui lòng nhập Tên đăng nhập và Mật khẩu!"
            self.errorMessage = msg
            completion?(false, msg)
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.successMessage = nil
        
        let pHash = AuthManager.hashPassword(p)
        let payload: [String: Any] = [
            "action": "LOGIN",
            "username": u,
            "passwordHash": pHash
        ]
        
        sendPostRequest(payload: payload) { success, json, err in
            DispatchQueue.main.async {
                self.isLoading = false
                if success, let json = json {
                    let status = json["status"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    if status == "SUCCESS" {
                        let role = json["role"] as? String ?? "FREE"
                        let expire = json["expireDate"] as? String ?? "2099-12-31"
                        let pts = json["points"] as? Int ?? 0
                        self.saveSession(username: u, role: role, expireDate: expire, points: pts)
                        self.successMessage = "Đăng nhập thành công! Chào mừng \(u)."
                        completion?(true, "Đăng nhập thành công!")
                    } else {
                        let errorMsg = msg.isEmpty ? "Đăng nhập thất bại. Vui lòng kiểm tra lại!" : msg
                        self.errorMessage = errorMsg
                        completion?(false, errorMsg)
                    }
                } else {
                    let errorMsg = err ?? "Không thể kết nối đến máy chủ xác thực!"
                    self.errorMessage = errorMsg
                    completion?(false, errorMsg)
                }
            }
        }
    }
    
    /// Đăng ký tài khoản mới
    public func register(user: String, pass: String, completion: ((Bool, String) -> Void)? = nil) {
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pass.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty || p.isEmpty {
            let msg = "Vui lòng nhập Tên đăng nhập và Mật khẩu mới!"
            self.errorMessage = msg
            completion?(false, msg)
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.successMessage = nil
        
        let uid = "usr_" + UUID().uuidString.prefix(8).lowercased()
        let pHash = AuthManager.hashPassword(p)
        let payload: [String: Any] = [
            "action": "REGISTER",
            "userId": uid,
            "username": u,
            "passwordHash": pHash
        ]
        
        sendPostRequest(payload: payload) { success, json, err in
            DispatchQueue.main.async {
                self.isLoading = false
                if success, let json = json {
                    let status = json["status"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    if status == "SUCCESS" {
                        let successMsg = "Đăng ký thành công! Hãy chuyển sang tab Đăng Nhập để sử dụng."
                        self.successMessage = successMsg
                        completion?(true, successMsg)
                    } else {
                        let errorMsg = msg.isEmpty ? "Đăng ký thất bại. Tên người dùng có thể đã tồn tại!" : msg
                        self.errorMessage = errorMsg
                        completion?(false, errorMsg)
                    }
                } else {
                    let errorMsg = err ?? "Không thể kết nối đến máy chủ xác thực!"
                    self.errorMessage = errorMsg
                    completion?(false, errorMsg)
                }
            }
        }
    }
    
    /// Kiểm tra trạng thái bản quyền & tài khoản trực tiếp từ Google Apps Script
    public func checkStatus(silent: Bool = false, completion: ((Bool, String) -> Void)? = nil) {
        guard !username.isEmpty else { return }
        
        if !silent {
            self.isLoading = true
            self.errorMessage = nil
            self.successMessage = nil
        }
        
        let payload: [String: Any] = [
            "action": "CHECK_STATUS",
            "username": username
        ]
        
        sendPostRequest(payload: payload) { success, json, err in
            DispatchQueue.main.async {
                if !silent { self.isLoading = false }
                if success, let json = json {
                    let status = json["status"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    if status == "SUCCESS" {
                        let role = json["role"] as? String ?? "FREE"
                        let expire = json["expireDate"] as? String ?? "2099-12-31"
                        let pts = json["points"] as? Int ?? 0
                        self.saveSession(username: self.username, role: role, expireDate: expire, points: pts)
                        if !silent {
                            self.successMessage = "Xác thực bản quyền thành công! Hạn dùng: \(expire)"
                        }
                        completion?(true, "Xác thực thành công!")
                    } else {
                        let errorMsg = msg.isEmpty ? "Tài khoản không hợp lệ hoặc đã bị khóa!" : msg
                        if !silent { self.errorMessage = errorMsg }
                        self.logout()
                        completion?(false, errorMsg)
                    }
                } else {
                    if !silent {
                        let errorMsg = err ?? "Không thể kết nối đến máy chủ xác thực!"
                        self.errorMessage = errorMsg
                        completion?(false, errorMsg)
                    }
                }
            }
        }
    }
    
    private func sendPostRequest(payload: [String: Any], completion: @escaping (Bool, [String: Any]?, String?) -> Void) {
        guard let url = URL(string: defaultServerUrl) else {
            completion(false, nil, "Địa chỉ máy chủ không hợp lệ")
            return
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(false, nil, "Lỗi đóng gói dữ liệu JSON")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = httpBody
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20.0
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, nil, error.localizedDescription)
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(false, nil, "Không nhận được phản hồi từ máy chủ")
                return
            }
            
            // Kiểm tra trường hợp trả về trang lỗi HTML
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("<") || text.localizedCaseInsensitiveContains("<!doctype") {
                completion(false, nil, "Máy chủ trả về trang HTML. Vui lòng kiểm tra quyền chia sẻ Web App (Anyone).")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(true, json, nil)
                } else {
                    completion(false, nil, "Định dạng dữ liệu không hợp lệ")
                }
            } catch {
                completion(false, nil, "Lỗi phân tích cú pháp phản hồi: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
}
