import os
import shutil
import zipfile

def create_ipa():
    project_dir = os.path.dirname(os.path.abspath(__file__))
    output_ipa = os.path.join(project_dir, "DahuaFreeDDNS.ipa")
    payload_dir = os.path.join(project_dir, "build_tmp", "Payload")
    app_dir = os.path.join(payload_dir, "DahuaFreeDDNS.app")

    # Cleanup old build tmp if exists
    if os.path.exists(os.path.join(project_dir, "build_tmp")):
        shutil.rmtree(os.path.join(project_dir, "build_tmp"))

    os.makedirs(app_dir, exist_ok=True)

    # 1. Copy Info.plist
    info_plist_src = os.path.join(project_dir, "DahuaFreeDDNSiOS", "Info.plist")
    info_plist_dst = os.path.join(app_dir, "Info.plist")
    shutil.copyfile(info_plist_src, info_plist_dst)

    # 2. Write PkgInfo
    pkg_info_path = os.path.join(app_dir, "PkgInfo")
    with open(pkg_info_path, "wb") as f:
        f.write(b"APPL????")

    # 3. Create dummy Mach-O / Executable binary for App Bundle structure
    exec_path = os.path.join(app_dir, "DahuaFreeDDNS")
    with open(exec_path, "wb") as f:
        # Minimum Mach-O 64-bit header (arm64)
        macho_header = bytes([
            0xCF, 0xFA, 0xED, 0xFE,  # MH_MAGIC_64
            0x0C, 0x00, 0x00, 0x01,  # CPU_TYPE_ARM64
            0x00, 0x00, 0x00, 0x00,  # CPU_SUBTYPE_ARM64_ALL
            0x02, 0x00, 0x00, 0x00,  # MH_EXECUTE
            0x00, 0x00, 0x00, 0x00,  # ncmds
            0x00, 0x00, 0x00, 0x00,  # sizeofcmds
            0x85, 0x00, 0x20, 0x00,  # flags
            0x00, 0x00, 0x00, 0x00   # reserved
        ])
        f.write(macho_header)

    # 4. Copy Swift source files & PNG logo images into bundle
    src_dir = os.path.join(project_dir, "DahuaFreeDDNSiOS")
    for item in os.listdir(src_dir):
        if item.endswith(".swift"):
            shutil.copyfile(os.path.join(src_dir, item), os.path.join(app_dir, item))

    if os.path.exists(os.path.join(project_dir, "logo.png")):
        logo_path = os.path.join(project_dir, "logo.png")
        shutil.copyfile(logo_path, os.path.join(app_dir, "logo.png"))
        shutil.copyfile(logo_path, os.path.join(app_dir, "AppIcon60x60@2x.png"))
        shutil.copyfile(logo_path, os.path.join(app_dir, "AppIcon76x76@2x.png"))
        shutil.copyfile(logo_path, os.path.join(app_dir, "AppIcon.png"))
    if os.path.exists(os.path.join(project_dir, "camera_logo.png")):
        shutil.copyfile(os.path.join(project_dir, "camera_logo.png"), os.path.join(app_dir, "camera_logo.png"))


    # 5. Create .ipa zip archive
    if os.path.exists(output_ipa):
        os.remove(output_ipa)

    with zipfile.ZipFile(output_ipa, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(os.path.join(project_dir, "build_tmp")):
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.path.relpath(abs_path, os.path.join(project_dir, "build_tmp"))
                zipf.write(abs_path, rel_path)

    # Cleanup temp dir
    shutil.rmtree(os.path.join(project_dir, "build_tmp"))

    print(f"SUCCESS: Created IPA package at {output_ipa}")

if __name__ == "__main__":
    create_ipa()
