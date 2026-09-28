import os

index_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\index.html"
b64_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\camera_logo_b64_utf8.txt"

with open(b64_path, "r", encoding="utf-8") as f:
    b64_str = f.read().strip()

with open(index_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add cameraLogoBase64String near script start
if "const cameraLogoBase64String =" not in content:
    content = content.replace(
        "<script>",
        f'<script>\n        const cameraLogoBase64String = "{b64_str}";\n'
    )

with open(index_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated index.html with base64 string successfully!")
