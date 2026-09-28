import http.server
import socketserver
import socket
import os

PORT = 8080

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Connect to an external IP to determine local network IP interface
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def main():
    project_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(project_dir)
    
    local_ip = get_local_ip()
    handler = http.server.SimpleHTTPRequestHandler

    print("=" * 65)
    print(" 🚀 DAHUA FREE DDNS iOS WEB APP SERVER IS RUNNING!")
    print("=" * 65)
    print(f"\n📲 TRÊN IPHONE KHỦNG CÙNG MẠNG WI-FI, MỞ SAFARI VÀ TRUY CẬP:")
    print(f"   👉 http://{local_ip}:{PORT}\n")
    print("📌 HƯỚNG DẪN TẠO ỨNG DỤNG NATIVE TRÊN IPHONE:")
    print("   1. Mở liên kết trên bằng Safari trên iPhone.")
    print("   2. Nhấn nút 'Chia sẻ' (Share) biểu tượng hình vuông có mũi tên lên.")
    print("   3. Chọn 'Thêm vào Màn hình chính' ('Add to Home Screen').")
    print("   4. Ứng dụng sẽ xuất hiện ở Màn hình chính iPhone như 1 App iOS xịn!\n")
    print("=" * 65)

    with socketserver.TCPServer(("", PORT), handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nĐã dừng Server.")

if __name__ == "__main__":
    main()
