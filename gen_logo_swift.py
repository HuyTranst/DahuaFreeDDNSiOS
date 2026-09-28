import os

b64_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\camera_logo_b64_utf8.txt"
out_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\DahuaFreeDDNSiOS\CameraLogoData.swift"

with open(b64_path, "r", encoding="utf-8") as f:
    b64 = f.read().strip()

swift_code = f'''import Foundation

public let cameraLogoBase64String = "{b64}"
'''

with open(out_path, "w", encoding="utf-8") as f:
    f.write(swift_code)

print("Created CameraLogoData.swift successfully!")
