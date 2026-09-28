import os

swift_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\DahuaFreeDDNSiOS\CameraLogoData.swift"
index_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\index.html"
b64_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\camera_logo_b64_utf8.txt"

with open(b64_path, "rb") as f:
    raw_bytes = f.read()

# Strip UTF-8 BOM if present (b'\xef\xbb\xbf')
if raw_bytes.startswith(b'\xef\xbb\xbf'):
    raw_bytes = raw_bytes[3:]

b64_clean = raw_bytes.decode('utf-8').strip()

print(f"Clean Base64 length: {len(b64_clean)}, starts with: {b64_clean[:15]}")

# Write clean CameraLogoData.swift
swift_code = f'''import Foundation

public let cameraLogoBase64String = "{b64_clean}"
'''

with open(swift_path, "w", encoding="utf-8") as f:
    f.write(swift_code)

# Write clean base64 into index.html
with open(index_path, "r", encoding="utf-8") as f:
    index_content = f.read()

import re
index_content = re.sub(
    r'const cameraLogoBase64String = "[^"]+";',
    f'const cameraLogoBase64String = "{b64_clean}";',
    index_content
)

with open(index_path, "w", encoding="utf-8") as f:
    f.write(index_content)

print("SUCCESS: Stripped UTF-8 BOM from Base64 string in Swift & HTML!")
