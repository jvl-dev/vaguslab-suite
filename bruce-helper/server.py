"""
Bruce Helper WebSocket Server
Handles encryption/decryption of accession numbers for Bruce browser app
Monitors DICOM state file and pushes study updates to connected clients
"""

import asyncio
import json
import base64
import logging
import re
import os
import secrets
from datetime import datetime
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
import websockets
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
PORT = 8765
# SECRET_KEY is initialised after logging is configured below.

# Paths (use absolute paths for reliability)
script_dir = os.path.abspath(os.path.dirname(__file__) or '.')
data_dir = os.path.join(script_dir, 'data')
log_dir = os.path.join(script_dir, 'logs')

# Create directories with error handling
try:
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)
except Exception as e:
    # Print to console if directory creation fails before logging is set up
    print(f"ERROR: Failed to create directories: {e}")
    print(f"script_dir: {script_dir}")
    print(f"data_dir: {data_dir}")
    print(f"log_dir: {log_dir}")
    raise


def _resolve_state_file():
    """Resolve the DICOM state file path.

    Checks (in order):
    1. Dev layout: ../dicom-service/data/current_study.json
    2. Production:  %LOCALAPPDATA%/vaguslab/dicom-service/data/current_study.json
    3. Fallback:    local data/current_study.json
    """
    dev_path = os.path.join(script_dir, '..', 'dicom-service', 'data', 'current_study.json')
    if os.path.isdir(os.path.dirname(dev_path)):
        return os.path.normpath(dev_path)

    local_appdata = os.environ.get('LOCALAPPDATA', '')
    if local_appdata:
        prod_path = os.path.join(local_appdata, 'vaguslab', 'dicom-service', 'data', 'current_study.json')
        if os.path.isdir(os.path.dirname(prod_path)):
            return prod_path

    return os.path.join(data_dir, 'current_study.json')


STATE_FILE = _resolve_state_file()
PID_FILE   = os.path.join(data_dir, "server.pid")
log_file = os.path.join(log_dir, 'websocket-server.log')

# Connected clients (for broadcasting)
connected_clients = set()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Encryption key — persisted in data/server.key (32 random bytes).
# Generated automatically on first run; never stored in the registry or
# environment variables.  Delete server.key to rotate the key (all existing
# accession tokens held by browsers will become invalid).
# ---------------------------------------------------------------------------
_KEY_FILE = os.path.join(data_dir, "server.key")


def _load_or_generate_key() -> bytes:
    """Load the AES-256 key from data/server.key, generating it if absent."""
    if os.path.exists(_KEY_FILE):
        try:
            with open(_KEY_FILE, "rb") as f:
                key = f.read()
            if len(key) == 32:
                logger.info("Encryption key loaded from data/server.key")
                return key
            logger.warning(
                f"data/server.key is {len(key)} bytes (expected 32) — regenerating"
            )
        except OSError as e:
            logger.warning(f"Could not read data/server.key: {e} — regenerating")

    key = secrets.token_bytes(32)
    try:
        with open(_KEY_FILE, "wb") as f:
            f.write(key)
        logger.info("Generated new encryption key — saved to data/server.key")
    except OSError as e:
        # Non-fatal: key works for this session but won't persist across restarts
        logger.error(f"Could not persist encryption key to data/server.key: {e}")
    return key


SECRET_KEY = _load_or_generate_key()


def encrypt_accession(accession: str, key: bytes) -> str:
    """
    Encrypt accession number using AES-256-CBC
    Returns: "v1:<base64(IV + ciphertext)>"
    """
    try:
        # Generate random IV (16 bytes for AES)
        iv = os.urandom(16)

        # Create cipher
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        encryptor = cipher.encryptor()

        # Pad plaintext to block size (16 bytes for AES)
        padder = padding.PKCS7(128).padder()
        padded_data = padder.update(accession.encode('utf-8')) + padder.finalize()

        # Encrypt
        ciphertext = encryptor.update(padded_data) + encryptor.finalize()

        # Prepend IV to ciphertext and encode as base64
        result = iv + ciphertext
        b64_result = base64.b64encode(result).decode('ascii')

        return f"v1:{b64_result}"
    except Exception as e:
        logger.error(f"Encryption error: {e}")
        raise


def decrypt_accession(token: str, key: bytes) -> str:
    """
    Decrypt accession token
    Returns: original accession number
    """
    try:
        # Verify format
        if not token.startswith("v1:"):
            raise ValueError("Invalid token format")

        # Decode base64
        b64_data = token[3:]  # Remove "v1:" prefix
        data = base64.b64decode(b64_data)

        # Extract IV (first 16 bytes) and ciphertext
        iv = data[:16]
        ciphertext = data[16:]

        # Create cipher
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()

        # Decrypt
        padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()

        # Unpad
        unpadder = padding.PKCS7(128).unpadder()
        plaintext = unpadder.update(padded_plaintext) + unpadder.finalize()

        return plaintext.decode('utf-8')
    except Exception as e:
        logger.error(f"Decryption error: {e}")
        raise


def _extract_core_acc(acc: str) -> str:
    """Strip split suffixes; return up to and including the modality code."""
    if not acc:
        return ""
    m = re.match(r'^(.+?-(CT|MR|US|DX|CR|MG|PT|NM|XA))', acc)
    if m:
        return m.group(0)
    return re.sub(r'_\d+$', '', acc)


def get_study_metadata(accession: str) -> dict:
    """
    Return study metadata for a manually-supplied accession number by matching
    it against the current DICOM state file written by dicom_monitor.py.
    Returns unknown defaults if no matching study is loaded.
    """
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, 'r', encoding='utf-8-sig') as f:
                dicom_data = json.load(f)

            if dicom_data and any(dicom_data.values()):
                request_core = _extract_core_acc(accession)
                dicom_core   = _extract_core_acc(dicom_data.get("Acc", ""))

                if request_core and dicom_core and request_core == dicom_core:
                    age_str = dicom_data.get("Age", "")
                    try:
                        patient_age = int(age_str[:-1].lstrip('0') or '0') if age_str.endswith('Y') else 0
                    except (ValueError, TypeError):
                        patient_age = 0

                    sex = dicom_data.get("Sex", "").strip().upper()
                    if sex not in ("M", "F", "O"):
                        sex = "U"

                    return {
                        "modality":         dicom_data.get("Mod", "UN"),
                        "studyDescription": dicom_data.get("StudyDesc", "Unknown Study"),
                        "patientAge":       patient_age,
                        "patientGender":    sex,
                    }
                else:
                    logger.warning(f"Accession mismatch: requested={request_core}, current={dicom_core}")
    except Exception as e:
        logger.warning(f"Failed to read DICOM state file: {e}")

    logger.info("No matching DICOM study loaded for manual encrypt request")
    return {
        "modality":         "UN",
        "studyDescription": "Unknown Study",
        "patientAge":       0,
        "patientGender":    "U",
    }


# ==============================================
# File Watching & Broadcasting
# ==============================================

class StudyFileHandler(FileSystemEventHandler):
    """Watches current_study.json and triggers broadcasts"""

    def __init__(self, loop):
        self.loop = loop
        self.last_study_hash = None

    def on_modified(self, event):
        logger.info(f"File modified event: {event.src_path}")
        if event.src_path.endswith("current_study.json"):
            logger.info("current_study.json modified - triggering broadcast")
            # Schedule broadcast in the event loop
            asyncio.run_coroutine_threadsafe(
                broadcast_study_update(),
                self.loop
            )
        else:
            logger.debug(f"Ignoring modification to: {event.src_path}")


async def broadcast_study_update():
    """Read current_study.json and broadcast to all connected clients"""
    try:
        logger.info(f"broadcast_study_update called, connected clients: {len(connected_clients)}")

        if not os.path.exists(STATE_FILE):
            logger.info("State file does not exist - sending study_cleared")
            await broadcast_study_cleared()
            return

        # Read DICOM state file (use utf-8-sig to handle BOM if present)
        with open(STATE_FILE, 'r', encoding='utf-8-sig') as f:
            dicom_data = json.load(f)

        logger.info(f"Read DICOM data: {dicom_data}")

        # Check if we have valid study data
        accession = dicom_data.get("Acc", "")
        if not accession or not any(dicom_data.values()):
            # No study or empty data - send study_cleared
            logger.info("No valid accession in data - sending study_cleared")
            await broadcast_study_cleared()
            return

        # Parse DICOM data
        age_str = dicom_data.get("Age", "")
        try:
            patient_age = int(age_str[:-1].lstrip('0') or '0') if age_str.endswith('Y') else 0
        except (ValueError, TypeError):
            patient_age = 0

        sex = dicom_data.get("Sex", "").strip().upper()
        if sex not in ["M", "F", "O"]:
            sex = "U"

        # Encrypt accession
        token = encrypt_accession(accession, SECRET_KEY)

        # Build study_update message
        message = {
            "type": "study_update",
            "accessionToken": token,
            "modality": dicom_data.get("Mod", "UN"),
            "studyDescription": dicom_data.get("StudyDesc", "Unknown Study"),
            "patientAge": patient_age,
            "patientGender": sex
        }

        # Broadcast to all connected clients
        if connected_clients:
            logger.info(f"Broadcasting study_update to {len(connected_clients)} clients",
                       extra={"accession": accession, "modality": message["modality"]})

            # Send to all clients concurrently; log individual send failures
            results = await asyncio.gather(
                *[client.send(json.dumps(message)) for client in connected_clients],
                return_exceptions=True,
            )
            for exc in results:
                if isinstance(exc, Exception):
                    logger.warning(f"Failed to deliver study_update to a client: {exc}")

    except Exception as e:
        logger.error(f"Broadcast study_update failed: {e}")


async def broadcast_study_cleared():
    """Broadcast that no study is currently active"""
    try:
        message = {
            "type": "study_cleared"
        }

        if connected_clients:
            logger.info(f"Broadcasting study_cleared to {len(connected_clients)} clients")

            results = await asyncio.gather(
                *[client.send(json.dumps(message)) for client in connected_clients],
                return_exceptions=True,
            )
            for exc in results:
                if isinstance(exc, Exception):
                    logger.warning(f"Failed to deliver study_cleared to a client: {exc}")

    except Exception as e:
        logger.error(f"Broadcast study_cleared failed: {e}")


async def handle_message(websocket, message_text):
    """Handle incoming WebSocket messages"""
    try:
        # Parse JSON
        message = json.loads(message_text)
        action = message.get("action")
        request_id = message.get("requestId", 0)

        logger.info(f"Received action: {action}, requestId: {request_id}")

        # Route to appropriate handler
        if action == "encrypt":
            await handle_encrypt(websocket, message, request_id)
        elif action == "decrypt":
            await handle_decrypt(websocket, message, request_id)
        elif action == "ping":
            await handle_ping(websocket, message, request_id)
        else:
            await send_error(websocket, request_id, f"Unknown action: {action}")

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        await send_error(websocket, 0, "Invalid JSON")
    except Exception as e:
        logger.error(f"Message handling error: {e}")
        await send_error(websocket, 0, str(e))


async def handle_encrypt(websocket, message, request_id):
    """Handle encryption request"""
    try:
        accession = message.get("accession")
        if not accession:
            await send_error(websocket, request_id, "Missing 'accession' field")
            return

        # Basic input validation: printable ASCII only, reasonable length
        if not isinstance(accession, str) or len(accession) > 128:
            await send_error(websocket, request_id, "Invalid accession value")
            return
        if not re.match(r'^[\x20-\x7E]+$', accession):
            await send_error(websocket, request_id, "Accession contains invalid characters")
            return

        # Encrypt accession
        token = encrypt_accession(accession, SECRET_KEY)

        # Get metadata
        metadata = get_study_metadata(accession)

        # Build response
        response = {
            "type": "encrypt_response",
            "requestId": request_id,
            "accessionToken": token,
            "modality": metadata["modality"],
            "studyDescription": metadata["studyDescription"],
            "patientAge": metadata["patientAge"],
            "patientGender": metadata["patientGender"]
        }

        logger.info(f"Encryption successful (len={len(accession)})")
        await websocket.send(json.dumps(response))

    except Exception as e:
        logger.error(f"Encryption handler error: {e}")
        await send_error(websocket, request_id, f"Encryption failed: {str(e)}")


async def handle_decrypt(websocket, message, request_id):
    """Handle decryption request"""
    try:
        token = message.get("token")
        if not token:
            await send_error(websocket, request_id, "Missing 'token' field")
            return

        # Decrypt token
        accession = decrypt_accession(token, SECRET_KEY)

        # Build response
        response = {
            "type": "decrypt_response",
            "requestId": request_id,
            "accession": accession
        }

        logger.info(f"Decryption successful")
        await websocket.send(json.dumps(response))

    except Exception as e:
        logger.error(f"Decryption handler error: {e}")
        await send_error(websocket, request_id, f"Decryption failed: {str(e)}")


async def handle_ping(websocket, message, request_id):
    """Handle ping request"""
    try:
        response = {
            "type": "pong",
            "requestId": request_id,
            "timestamp": datetime.now().strftime("%Y%m%d%H%M%S")
        }

        await websocket.send(json.dumps(response))

    except Exception as e:
        logger.error(f"Ping handler error: {e}")
        await send_error(websocket, request_id, str(e))


async def send_error(websocket, request_id, error_message):
    """Send error response"""
    response = {
        "type": "error",
        "requestId": request_id,
        "message": error_message
    }
    await websocket.send(json.dumps(response))


async def handler(websocket):
    """Main WebSocket connection handler"""
    client_address = websocket.remote_address
    logger.info(f"Client connected: {client_address}")

    # Add client to connected set
    connected_clients.add(websocket)

    try:
        # Send current study state immediately on connection
        await broadcast_study_update()

        # Handle incoming messages
        async for message in websocket:
            await handle_message(websocket, message)
    except websockets.exceptions.ConnectionClosed:
        logger.info(f"Client disconnected: {client_address}")
    except Exception as e:
        logger.error(f"Connection error: {e}")
    finally:
        # Remove client from connected set
        connected_clients.discard(websocket)
        logger.info(f"Connection closed: {client_address}")


async def main():
    """Start WebSocket server and file watcher"""
    logger.info(f"Starting WebSocket server on ws://localhost:{PORT}")

    loop = asyncio.get_running_loop()

    # Start file watcher for current_study.json (watches the shared dicom-service data dir)
    event_handler = StudyFileHandler(loop)
    observer = Observer()
    watch_dir = os.path.dirname(STATE_FILE) or "."
    observer.schedule(event_handler, watch_dir, recursive=False)
    observer.start()
    logger.info(f"Watching for study updates: {STATE_FILE}")

    try:
        async with websockets.serve(handler, "localhost", PORT):
            logger.info(f"Server ready - listening on port {PORT}")
            await asyncio.Future()  # Run forever
    finally:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    print("="*60)
    print("Bruce Helper WebSocket Server")
    print(f"Script directory: {script_dir}")
    print(f"Data directory: {data_dir}")
    print(f"Log directory: {log_dir}")
    print(f"State file: {STATE_FILE}")
    print("="*60)

    # Write PID file so AHK can cleanly kill this process on restart.
    import atexit
    try:
        with open(PID_FILE, "w") as _f:
            _f.write(str(os.getpid()))
        @atexit.register
        def _remove_pid():
            try:
                os.unlink(PID_FILE)
            except OSError:
                pass
    except OSError:
        pass  # Non-fatal — AHK falls back to its stored PID

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
        print("\nServer stopped by user")
    except Exception as e:
        error_msg = f"Server error: {e}"
        print(f"\nERROR: {error_msg}")
        print(f"Error type: {type(e).__name__}")
        import traceback
        traceback.print_exc()
        try:
            logger.error(error_msg)
        except:
            pass  # Logging might not be set up yet
