import os
import glob

swift_dir = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\DahuaFreeDDNSiOS"
swift_files = glob.glob(os.path.join(swift_dir, "*.swift"))

print(f"Found {len(swift_files)} swift files:")

for fpath in swift_files:
    fname = os.path.basename(fpath)
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()

    # Check balanced braces
    open_b = code.count('{')
    close_b = code.count('}')
    open_p = code.count('(')
    close_p = code.count(')')
    
    print(f"File {fname}: length={len(code)}, braces={{ {open_b} / }} {close_b}, parens=( {open_p} / ) {close_p}")
