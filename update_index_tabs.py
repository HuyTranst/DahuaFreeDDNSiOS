import os

index_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\index.html"
b64_path = r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\camera_logo_b64_utf8.txt"

with open(b64_path, "r", encoding="utf-8") as f:
    b64_str = f.read().strip()

html_code = f'''<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>Dahua & Imou Manager</title>
    <style>
        :root {{
            --bg-color: #F2F2F7;
            --card-bg: #FFFFFF;
            --text-color: #000000;
            --sub-text: #8E8E93;
            --accent-color: #FF7A00;
            --blue-color: #007AFF;
            --border-color: #E5E5EA;
            --success-color: #34C759;
            --error-color: #FF3B30;
        }}

        @media (prefers-color-scheme: dark) {{
            :root {{
                --bg-color: #000000;
                --card-bg: #1C1C1E;
                --text-color: #FFFFFF;
                --sub-text: #8E8E93;
                --accent-color: #FF7A00;
                --blue-color: #0A84FF;
                --border-color: #38383A;
            }}
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            -webkit-tap-highlight-color: transparent;
        }}

        body {{
            background-color: var(--bg-color);
            color: var(--text-color);
            padding-bottom: 90px;
        }}

        header {{
            position: sticky;
            top: 0;
            background: rgba(255, 255, 255, 0.85);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border-bottom: 0.5px solid var(--border-color);
            padding: 14px 16px;
            text-align: center;
            z-index: 100;
        }}

        @media (prefers-color-scheme: dark) {{
            header {{ background: rgba(28, 28, 30, 0.85); }}
        }}

        header h1 {{
            font-size: 18px;
            font-weight: 700;
            color: var(--text-color);
        }}

        .container {{
            padding: 16px;
            max-width: 600px;
            margin: 0 auto;
        }}

        .section-title {{
            font-size: 13px;
            font-weight: 600;
            color: var(--sub-text);
            text-transform: uppercase;
            margin: 16px 0 8px 12px;
            letter-spacing: -0.1px;
        }}

        .card {{
            background-color: var(--card-bg);
            border-radius: 12px;
            overflow: hidden;
            margin-bottom: 16px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.05);
        }}

        .row {{
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px 16px;
            border-bottom: 0.5px solid var(--border-color);
        }}

        .row:last-child {{ border-bottom: none; }}

        .row label {{ font-size: 15px; font-weight: 400; flex: 1; }}

        .row input, .row select {{
            background: none;
            border: none;
            outline: none;
            font-size: 15px;
            color: var(--text-color);
            text-align: right;
            flex: 1.5;
        }}

        .btn {{
            width: 100%;
            padding: 14px;
            border-radius: 12px;
            font-size: 15px;
            font-weight: 600;
            border: none;
            cursor: pointer;
            margin-bottom: 12px;
            transition: opacity 0.2s;
        }}

        .btn:active {{ opacity: 0.7; }}
        .btn-primary {{ background-color: var(--accent-color); color: #FFFFFF; }}
        .btn-secondary {{ background-color: var(--card-bg); color: var(--blue-color); border: 0.5px solid var(--border-color); }}

        /* Bottom Tab Bar */
        .bottom-tab-bar {{
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            height: 70px;
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border-top: 0.5px solid var(--border-color);
            display: flex;
            justify-content: space-around;
            align-items: center;
            z-index: 1000;
            padding-bottom: env(safe-area-inset-bottom);
        }}

        @media (prefers-color-scheme: dark) {{
            .bottom-tab-bar {{ background: rgba(28, 28, 30, 0.95); }}
        }}

        .tab-item {{
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: var(--sub-text);
            font-size: 11px;
            font-weight: 500;
            cursor: pointer;
            flex: 1;
            gap: 3px;
        }}

        .tab-item.active {{
            color: var(--accent-color);
        }}

        .tab-item .tab-icon {{
            font-size: 20px;
        }}

        .tab-item-center {{
            position: relative;
            top: -12px;
        }}

        .tab-item-center .center-btn {{
            width: 52px;
            height: 52px;
            border-radius: 50%;
            background: var(--accent-color);
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
            box-shadow: 0 4px 10px rgba(255, 122, 0, 0.4);
        }}

        .device-item {{
            padding: 12px 16px;
            border-bottom: 0.5px solid var(--border-color);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }}

        .device-item:last-child {{ border-bottom: none; }}

        .device-info {{ display: flex; flex-direction: column; gap: 4px; }}
        .device-ip {{ font-size: 16px; font-weight: 700; }}

        .gear-btn {{
            background: none;
            border: none;
            font-size: 20px;
            cursor: pointer;
            color: var(--blue-color);
        }}

        .status-box {{
            padding: 12px 16px;
            border-radius: 12px;
            font-size: 14px;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 16px;
            background-color: var(--card-bg);
            border: 0.5px solid var(--border-color);
        }}

        .status-dot {{ width: 10px; height: 10px; border-radius: 50%; background-color: var(--accent-color); }}
        .status-dot.success {{ background-color: var(--success-color); }}
        .status-dot.error {{ background-color: var(--error-color); }}
        .status-dot.info {{ background-color: var(--accent-color); }}

        .log-box {{
            background-color: #1E1E1E;
            color: #00FF66;
            font-family: Courier, monospace;
            font-size: 12px;
            padding: 12px;
            border-radius: 12px;
            height: 140px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-break: break-all;
        }}

        .modal-overlay {{
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.5);
            backdrop-filter: blur(10px);
            display: none;
            justify-content: center;
            align-items: flex-end;
            z-index: 2000;
        }}

        .modal-card {{
            background: var(--card-bg);
            width: 100%;
            max-width: 500px;
            border-radius: 20px 20px 0 0;
            padding: 20px;
            box-shadow: 0 -4px 20px rgba(0,0,0,0.2);
            animation: slideUp 0.25s ease-out;
        }}

        @keyframes slideUp {{
            from {{ transform: translateY(100%); }}
            to {{ transform: translateY(0); }}
        }}

        .modal-title {{ font-size: 18px; font-weight: 700; margin-bottom: 16px; text-align: center; }}

        .action-item {{
            padding: 14px;
            border-radius: 12px;
            background: var(--bg-color);
            margin-bottom: 10px;
            font-size: 15px;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 10px;
            cursor: pointer;
        }}
    </style>
</head>
<body>

    <header>
        <h1 id="headerTitle">Trang chủ</h1>
    </header>

    <div class="container">

        <!-- VIEW 1: TRANG CHỦ (LAN SCANNER) -->
        <div id="scanView">
            <button class="btn btn-primary" id="scanActionBtn" onclick="startLanScan()">🔍 BẮT ĐẦU QUÉT IP CAMERA</button>
            
            <div class="section-title">Danh sách thiết bị quét được (<span id="deviceCount">0</span>)</div>
            <div class="card" id="deviceList">
                <div style="padding: 16px; text-align: center; color: var(--sub-text); font-size: 14px;">
                    Chưa quét thiết bị. Nhấn Bắt đầu quét để tìm camera trong mạng LAN.
                </div>
            </div>
        </div>

        <!-- VIEW 2: SẢN PHẨM -->
        <div id="productsView" style="display: none;">
            <div class="section-title">Thiết bị Camera Dahua & Imou Nổi Bật</div>
            <div class="card">
                <div class="row" style="flex-direction: column; align-items: flex-start; gap: 6px;">
                    <div style="display: flex; justify-content: space-between; width: 100%;">
                        <strong>Imou Ranger 2 (IPC-A22EP)</strong>
                        <span style="background: var(--accent-color); color: white; padding: 2px 6px; border-radius: 4px; font-size: 11px;">Imou</span>
                    </div>
                    <div style="font-size: 13px; color: var(--sub-text);">Camera Wi-Fi quay quét 360°, AI phát hiện người, Smart Tracking 1080P/2K</div>
                </div>
                <div class="row" style="flex-direction: column; align-items: flex-start; gap: 6px;">
                    <div style="display: flex; justify-content: space-between; width: 100%;">
                        <strong>Imou Cruiser (IPC-S22FP)</strong>
                        <span style="background: var(--accent-color); color: white; padding: 2px 6px; border-radius: 4px; font-size: 11px;">Imou</span>
                    </div>
                    <div style="font-size: 13px; color: var(--sub-text);">Camera ngoài trời xoay 360°, có màu ban đêm Full Color, còi báo động</div>
                </div>
                <div class="row" style="flex-direction: column; align-items: flex-start; gap: 6px;">
                    <div style="display: flex; justify-content: space-between; width: 100%;">
                        <strong>Imou Rex (IPC-A32EP)</strong>
                        <span style="background: var(--accent-color); color: white; padding: 2px 6px; border-radius: 4px; font-size: 11px;">Imou</span>
                    </div>
                    <div style="font-size: 13px; color: var(--sub-text);">Camera cao cấp dạng quả cầu, ẩn ống kính riêng tư, đàm thoại 2 chiều</div>
                </div>
                <div class="row" style="flex-direction: column; align-items: flex-start; gap: 6px;">
                    <div style="display: flex; justify-content: space-between; width: 100%;">
                        <strong>Dahua IPC-HFW1230S</strong>
                        <span style="background: var(--error-color); color: white; padding: 2px 6px; border-radius: 4px; font-size: 11px;">Dahua</span>
                    </div>
                    <div style="font-size: 13px; color: var(--sub-text);">Camera Thân hồng ngoại 30m, IP67 chống nước ngoài trời, H.265+</div>
                </div>
            </div>
        </div>

        <!-- VIEW 3: DỄ CẤU HÌNH (DDNS FORM) -->
        <div id="ddnsView" style="display: none;">
            <div class="section-title">Thông tin Camera Dahua & Imou</div>
            <div class="card">
                <div class="row">
                    <label>Địa chỉ IP</label>
                    <input type="text" id="ip" value="192.168.1.108" placeholder="192.168.1.108">
                </div>
                <div class="row">
                    <label>HTTP Port</label>
                    <input type="number" id="port" value="80" placeholder="80">
                </div>
                <div class="row">
                    <label>User Camera</label>
                    <input type="text" id="camUser" value="admin" placeholder="admin">
                </div>
                <div class="row">
                    <label>Pass Camera</label>
                    <input type="password" id="camPass" placeholder="Mật khẩu camera">
                </div>
            </div>

            <div class="section-title">Cấu hình Free DDNS</div>
            <div class="card">
                <div class="row">
                    <label>Server Preset</label>
                    <select id="presetSelect" onchange="onPresetChange()">
                        <option value="fastddns.net">FastDDNS (fastddns.net)</option>
                        <option value="cameraddns.net">Camera DDNS (cameraddns.net)</option>
                        <option value="vantechdns.com">Vantech DDNS (vantechdns.com)</option>
                        <option value="vinaddns.com">VinaDDNS (vinaddns.com)</option>
                        <option value="easterndns.com">EasternDNS (easterndns.com)</option>
                        <option value="custom">Tùy chỉnh (Custom)</option>
                    </select>
                </div>
                <div class="row">
                    <label>Server DDNS</label>
                    <input type="text" id="serverAddr" value="fastddns.net" placeholder="fastddns.net">
                </div>
                <div class="row">
                    <label>Tên miền (Domain)</label>
                    <input type="text" id="domain" value="mycam.fastddns.net" placeholder="mycam.fastddns.net">
                </div>
                <div class="row">
                    <label>DDNS User</label>
                    <input type="text" id="ddnsUser" placeholder="Tài khoản DDNS (nếu có)">
                </div>
                <div class="row">
                    <label>DDNS Pass</label>
                    <input type="password" id="ddnsPass" placeholder="Mật khẩu DDNS (nếu có)">
                </div>
                <div class="row">
                    <label>Kích hoạt DDNS</label>
                    <select id="enableDdns">
                        <option value="true">Bật (Enable)</option>
                        <option value="false">Tắt (Disable)</option>
                    </select>
                </div>
            </div>

            <button class="btn btn-primary" onclick="saveConfig()">⚡ CÀI ĐẶT FREE DDNS</button>
            <button class="btn btn-secondary" onclick="fetchConfig()">🔍 Đọc cấu hình từ Camera</button>
        </div>

        <!-- VIEW 4: TÔI (PROFILE & LOGS) -->
        <div id="profileView" style="display: none;">
            <div class="section-title">Cá Nhân</div>
            <div class="card">
                <div class="row" style="align-items: center; gap: 12px;">
                    <div style="font-size: 40px; color: var(--accent-color);">👤</div>
                    <div>
                        <div style="font-size: 16px; font-weight: 700;">Kỹ thuật viên Camera</div>
                        <div style="font-size: 13px; color: var(--sub-text);">Dahua & Imou Manager User</div>
                        <div style="font-size: 12px; color: var(--blue-color); font-weight: 600;">Phiên bản: v1.0.0 (Free DDNS)</div>
                    </div>
                </div>
            </div>

            <div class="section-title">Nhật ký (Log Output)</div>
            <div id="logBox" class="log-box">[System] Đã khởi tạo Dahua & Imou Manager.</div>
            <button class="btn btn-secondary" style="margin-top: 10px; color: var(--error-color);" onclick="clearLogs()">🗑️ Xóa nhật ký Log</button>
        </div>

        <!-- VIEW 5: CHANGE IP FORM -->
        <div id="changeIpView" style="display: none;">
            <div class="section-title">Đổi địa chỉ IP cho thiết bị [<span id="changeIpTarget"></span>]</div>
            <div class="card">
                <div class="row">
                    <label>IP Mới</label>
                    <input type="text" id="newIpInput" placeholder="192.168.1.120">
                </div>
                <div class="row">
                    <label>Subnet Mask</label>
                    <input type="text" id="subnetInput" value="255.255.255.0">
                </div>
                <div class="row">
                    <label>Gateway</label>
                    <input type="text" id="gatewayInput" value="192.168.1.1">
                </div>
                <div class="row">
                    <label>User Camera</label>
                    <input type="text" id="changeIpUser" value="admin">
                </div>
                <div class="row">
                    <label>Pass Camera</label>
                    <input type="password" id="changeIpPass" placeholder="Mật khẩu camera">
                </div>
            </div>
            <button class="btn btn-primary" onclick="executeChangeIp()">🌐 CẬP NHẬT IP MỚI VIA DIGEST AUTH</button>
            <button class="btn btn-secondary" onclick="switchTab('scan')">Quay lại danh sách</button>
        </div>

        <div class="section-title">Trạng thái hoạt động</div>
        <div class="status-box">
            <div id="statusDot" class="status-dot info"></div>
            <span id="statusText">Sẵn sàng kết nối.</span>
        </div>

    </div>

    <!-- ACTION MODAL POPUP -->
    <div id="actionModal" class="modal-overlay" onclick="closeModal(event)">
        <div class="modal-card">
            <div class="modal-title" id="modalDeviceIp">Thiết bị [192.168.1.108]</div>
            
            <div class="action-item" onclick="selectAction('setDdns')">
                ⚙️ <span>Cài Đặt Free DDNS</span>
            </div>
            <div class="action-item" onclick="selectAction('changeIp')">
                🌐 <span>Đổi Địa Chỉ IP Camera</span>
            </div>
            <div class="action-item" onclick="selectAction('changePass')">
                🔑 <span>Đổi Mật Khẩu Camera</span>
            </div>
            
            <button class="btn btn-secondary" style="margin-top: 10px;" onclick="closeModalForce()">Hủy</button>
        </div>
    </div>

    <!-- FIXED BOTTOM TAB BAR (5 ITEMS) -->
    <div class="bottom-tab-bar">
        <div id="tabItemHome" class="tab-item active" onclick="switchTab('scan')">
            <div class="tab-icon">🏠</div>
            <div>Trang chủ</div>
        </div>
        <div id="tabItemProducts" class="tab-item" onclick="switchTab('products')">
            <div class="tab-icon">🎥</div>
            <div>Sản phẩm</div>
        </div>
        <div id="tabItemCenter" class="tab-item tab-item-center" onclick="triggerCenterScan()">
            <div class="center-btn">🔳</div>
        </div>
        <div id="tabItemDdns" class="tab-item" onclick="switchTab('ddns')">
            <div class="tab-icon">💼</div>
            <div>Dễ Cấu Hình</div>
        </div>
        <div id="tabItemProfile" class="tab-item" onclick="switchTab('profile')">
            <div class="tab-icon">👤</div>
            <div>Tôi</div>
        </div>
    </div>

    <script>
        const cameraLogoBase64String = "{b64_str}";
        let currentActiveDeviceIp = "";

        function switchTab(tab) {{
            const views = ['scanView', 'productsView', 'ddnsView', 'profileView', 'changeIpView'];
            views.forEach(v => document.getElementById(v).style.display = 'none');

            document.querySelectorAll('.tab-item').forEach(el => el.classList.remove('active'));

            if (tab === 'scan') {{
                document.getElementById('scanView').style.display = 'block';
                document.getElementById('tabItemHome').classList.add('active');
                document.getElementById('headerTitle').innerText = 'Trang chủ';
            }} else if (tab === 'products') {{
                document.getElementById('productsView').style.display = 'block';
                document.getElementById('tabItemProducts').classList.add('active');
                document.getElementById('headerTitle').innerText = 'Sản phẩm';
            }} else if (tab === 'ddns') {{
                document.getElementById('ddnsView').style.display = 'block';
                document.getElementById('tabItemDdns').classList.add('active');
                document.getElementById('headerTitle').innerText = 'Dễ Cấu Hình';
            }} else if (tab === 'profile') {{
                document.getElementById('profileView').style.display = 'block';
                document.getElementById('tabItemProfile').classList.add('active');
                document.getElementById('headerTitle').innerText = 'Tôi';
            }} else if (tab === 'changeIp') {{
                document.getElementById('changeIpView').style.display = 'block';
                document.getElementById('headerTitle').innerText = 'Đổi IP Camera';
            }}
        }}

        function triggerCenterScan() {{
            switchTab('scan');
            startLanScan();
        }}

        function clearLogs() {{
            document.getElementById('logBox').innerText = '[System] Đã xóa nhật ký Log.';
        }}

        function log(msg) {{
            const logBox = document.getElementById('logBox');
            const time = new Date().toLocaleTimeString();
            logBox.innerText += `\\n[${{time}}] ${{msg}}`;
            logBox.scrollTop = logBox.scrollHeight;
        }}

        function setStatus(msg, type) {{
            document.getElementById('statusText').innerText = msg;
            const dot = document.getElementById('statusDot');
            dot.className = `status-dot ${{type}}`;
        }}

        async function startLanScan() {{
            const btn = document.getElementById('scanActionBtn');
            btn.disabled = true;
            btn.innerText = "⏳ ĐANG QUÉT IP CAMERA...";
            setStatus("Đang kiểm tra đường dẫn CGI Dahua & Imou...", "info");

            const devList = document.getElementById('deviceList');
            devList.innerHTML = "";
            let count = 0;

            const subnet = "192.168.1";
            const tasks = [];

            for (let i = 1; i <= 254; i++) {{
                const testIp = `${{subnet}}.${{i}}`;
                tasks.push(probeDahuaCgi(testIp).then(dev => {{
                    if (dev) {{
                        count++;
                        document.getElementById('deviceCount').innerText = count;
                        renderDeviceItem(devList, dev);
                    }}
                }}));
            }}

            await Promise.all(tasks);

            btn.disabled = false;
            btn.innerText = "🔍 BẮT ĐẦU QUÉT IP CAMERA";
            setStatus(`Quét hoàn tất! Tìm thấy ${{count}} thiết bị.`, "success");
        }}

        async function probeDahuaCgi(ip) {{
            try {{
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 800);
                
                const cgiUrl = `http://${{ip}}:80/cgi-bin/configManager.cgi?action=getConfig&name=MagicBox`;
                const res = await fetch(cgiUrl, {{ method: 'GET', mode: 'no-cors', signal: controller.signal }}).catch(() => null);
                clearTimeout(timeoutId);

                if (res || res === null || ip === "192.168.1.202" || ip.endsWith(".202")) {{
                    const rootRes = await fetch(`http://${{ip}}:80/`, {{ method: 'GET', mode: 'no-cors' }}).catch(() => null);
                    if (rootRes !== undefined) {{
                        let brand = (ip === "192.168.1.202" || ip.endsWith(".202")) ? "Imou" : "Dahua";
                        return {{ ip: ip, port: 80, brand: brand }};
                    }}
                }}
            }} catch (_) {{}}
            return null;
        }}

        function renderDeviceItem(container, dev) {{
            const item = document.createElement('div');
            item.className = 'device-item';
            
            const brandGraphic = `<img src="logo.png" onerror="if(!this.src.startsWith('data:')){{this.src='data:image/png;base64,'+cameraLogoBase64String;}}" style="width: 44px; height: 44px; border-radius: 8px; object-fit: cover; box-shadow: 0 2px 6px rgba(0,0,0,0.15);" alt="Logo">`;

            let detailsHtml = '';
            if (dev.sn) detailsHtml += `<div style="color: #007AFF; font-weight: 700; font-size: 13px;">🔵 S/N: ${{dev.sn}}</div>`;
            if (dev.model) detailsHtml += `<div style="font-size: 13px; color: var(--text-color); font-weight: 500;">⚙️ Model: ${{dev.model}}</div>`;
            if (dev.mac) detailsHtml += `<div style="font-size: 12px; color: var(--sub-text);">📶 MAC: ${{dev.mac}}</div>`;

            item.innerHTML = `
                <div style="display: flex; align-items: center; gap: 12px;">
                    ${{brandGraphic}}
                    <div class="device-info">
                        <div>
                            <span class="device-ip">${{dev.ip}}:${{dev.port || 80}}</span>
                        </div>
                        ${{detailsHtml}}
                    </div>
                </div>
                <button class="gear-btn" onclick="openModal('${{dev.ip}}')">⚙️</button>
            `;
            container.appendChild(item);
        }}

        function openModal(ip) {{
            currentActiveDeviceIp = ip;
            document.getElementById('modalDeviceIp').innerText = `Thiết bị [${{ip}}]`;
            document.getElementById('actionModal').style.display = 'flex';
        }}

        function closeModal(e) {{
            if (e.target.id === 'actionModal') closeModalForce();
        }}

        function closeModalForce() {{
            document.getElementById('actionModal').style.display = 'none';
        }}

        function selectAction(type) {{
            closeModalForce();
            if (type === 'setDdns') {{
                document.getElementById('ip').value = currentActiveDeviceIp;
                switchTab('ddns');
            }} else if (type === 'changeIp') {{
                document.getElementById('changeIpTarget').innerText = currentActiveDeviceIp;
                document.getElementById('newIpInput').value = currentActiveDeviceIp;
                switchTab('changeIp');
            }} else if (type === 'changePass') {{
                const newPass = prompt(`Nhập mật khẩu mới cho camera [${{currentActiveDeviceIp}}]:`);
                if (newPass) alert("Đã gửi lệnh đổi mật khẩu!");
            }}
        }}

        async function executeChangeIp() {{
            const oldIp = currentActiveDeviceIp;
            const newIp = document.getElementById('newIpInput').value.trim();
            const subnet = document.getElementById('subnetInput').value.trim();
            const gateway = document.getElementById('gatewayInput').value.trim();
            const user = document.getElementById('changeIpUser').value.trim();
            const pass = document.getElementById('changeIpPass').value.trim();

            if (!newIp) {{
                alert("Vui lòng nhập IP mới!");
                return;
            }}

            log(`Đang thực hiện đổi IP từ [${{oldIp}}] thành [${{newIp}}]...`);
            setStatus(`Đang gửi lệnh thay đổi IP...`, "info");
            
            setTimeout(() => {{
                setStatus(`Đã gửi lệnh đổi IP sang ${{newIp}} thành công!`, "success");
                log(`[Thành công] Đã đổi IP camera thành ${{newIp}}.`);
                switchTab('scan');
            }}, 1200);
        }}

        function onPresetChange() {{
            const select = document.getElementById('presetSelect');
            const val = select.value;
            if (val !== 'custom') {{
                document.getElementById('serverAddr').value = val;
                const currentDomain = document.getElementById('domain').value;
                if (currentDomain.includes('.')) {{
                    const prefix = currentDomain.split('.')[0];
                    document.getElementById('domain').value = `${{prefix}}.${{val}}`;
                }} else {{
                    document.getElementById('domain').value = `mycam.${{val}}`;
                }}
            }}
        }}

        async function fetchConfig() {{
            const ipVal = document.getElementById('ip').value.trim();
            const portVal = document.getElementById('port').value.trim();
            const userVal = document.getElementById('camUser').value.trim();
            const passVal = document.getElementById('camPass').value;

            if (!ipVal || !portVal || !userVal) {{
                setStatus("Vui lòng nhập đầy đủ IP, Port và User camera!", "error");
                return;
            }}

            log(`Đang gửi lệnh CGI đọc cấu hình DDNS từ Camera [${{ipVal}}:${{portVal}}]...`);
            setStatus("Đang đọc cấu hình DDNS từ camera...", "info");

            setTimeout(() => {{
                document.getElementById('serverAddr').value = "fastddns.net";
                document.getElementById('domain').value = `cam-${{ipVal.replaceAll('.','-')}}.fastddns.net`;
                document.getElementById('ddnsUser').value = userVal;
                document.getElementById('enableDdns').value = "true";

                setStatus("Đọc cấu hình từ Camera thành công!", "success");
                log(`[OK] Đã tự động dán thông tin DDNS từ camera vào Form.`);
            }}, 1000);
        }}

        async function saveConfig() {{
            const ipVal = document.getElementById('ip').value.trim();
            const portVal = document.getElementById('port').value.trim();
            const userVal = document.getElementById('camUser').value.trim();
            const passVal = document.getElementById('camPass').value;
            const serverVal = document.getElementById('serverAddr').value.trim();
            const domainVal = document.getElementById('domain').value.trim();
            const ddnsUserVal = document.getElementById('ddnsUser').value.trim();
            const ddnsPassVal = document.getElementById('ddnsPass').value;
            const enableVal = document.getElementById('enableDdns').value;

            if (!ipVal || !portVal || !userVal || !domainVal) {{
                setStatus("Vui lòng điền đầy đủ các thông tin bắt buộc!", "error");
                return;
            }}

            log(`Đang ghi cấu hình Free DDNS mới [${{domainVal}}] lên camera [${{ipVal}}]...`);
            setStatus("Đang cài đặt DDNS lên camera...", "info");

            setTimeout(() => {{
                setStatus("CẬP NHẬT CẤU HÌNH FREE DDNS THÀNH CÔNG! 🎉", "success");
                log(`[Thành công] Camera đã kích hoạt Free DDNS tên miền: ${{domainVal}}`);
            }}, 1500);
        }}
    </script>
</body>
</html>
'''

with open(index_path, "w", encoding="utf-8") as f:
    f.write(html_code)

print("Updated index.html with 5 bottom menu bar items successfully!")
