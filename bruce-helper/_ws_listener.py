"""Connect to the Bruce Helper WebSocket server and print all messages."""
import asyncio
import json
import sys
from datetime import datetime

try:
    import websockets
except ImportError:
    print("ERROR: websockets package not installed", file=sys.stderr)
    sys.exit(1)


async def listen():
    try:
        async with websockets.connect("ws://localhost:8765") as ws:
            print("Connected to ws://localhost:8765\n")
            async for msg in ws:
                now = datetime.now().strftime("%H:%M:%S")
                data = json.loads(msg)
                msg_type = data.get("type", "?")
                print(f"[{now}] {msg_type}")
                for k, v in data.items():
                    if k != "type":
                        print(f"  {k}: {v}")
                print()
    except ConnectionRefusedError:
        print("ERROR: No server running on port 8765", file=sys.stderr)
        print("Start the server first: test-server.bat  (or launch bruce-helper.ahk)", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)


asyncio.run(listen())
