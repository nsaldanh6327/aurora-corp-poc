import asyncio
import json
import shutil
import subprocess
import tempfile
import urllib.request
import websockets
import structlog

logger = structlog.get_logger()


async def authenticate_in_browser(proxy, auth_info, credentials, display_mode):
    user_data_dir = tempfile.mkdtemp(prefix="chrome-vpn-")
    cmd = [
        "google-chrome-stable",
        "--remote-debugging-port=9222",
        f"--user-data-dir={user_data_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        auth_info.login_url,
    ]
    logger.info("Launching Google Chrome for Keycloak SSO", url=auth_info.login_url)
    proc = subprocess.Popen(cmd)

    try:
        ws_url = None
        for _ in range(30):
            try:
                with urllib.request.urlopen("http://127.0.0", timeout=1) as resp:
                    tabs = json.loads(resp.read().decode())
                    for tab in tabs:
                        if tab.get("type") == "page" and "webSocketDebuggerUrl" in tab:
                            ws_url = tab["webSocketDebuggerUrl"]
                            break
                if ws_url:
                    break
            except Exception:
                await asyncio.sleep(0.5)

        if not ws_url:
            raise RuntimeError("Could not connect to Chrome remote debugging port 9222")

        async with websockets.connect(ws_url) as ws:
            await ws.send(json.dumps({"id": 1, "method": "Network.enable"}))
            await ws.recv()

            while True:
                await ws.send(json.dumps({"id": 2, "method": "Network.getAllCookies"}))
                msg = json.loads(await ws.recv())
                if msg.get("id") == 2:
                    cookies = msg.get("result", {}).get("cookies", [])
                    for c in cookies:
                        if c.get("name") == auth_info.token_cookie_name and c.get("value"):
                            logger.info("Captured SSO token from Chrome")
                            return c["value"]
                await asyncio.sleep(0.5)
    finally:
        proc.terminate()
        shutil.rmtree(user_data_dir, ignore_errors=True)
