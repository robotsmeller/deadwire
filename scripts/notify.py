"""Send a one-way notification to Telegram.

Reuses the bot the Claude channel already registered. This is the SEND path
only: a plain HTTPS POST, no bot process, no long polling, so it does not care
whether the Claude channel's receiver is running. Nothing here reads messages
back, which is deliberate. Rob actions what arrives on his phone by coming back
to the session, not by replying to the bot.

The token is read at runtime and scrubbed from every log line, because it sits
inside the request URL and urllib exception text leaks it otherwise.

Usage:
    python scripts/notify.py "Deadwire ready to test"
    echo "long message" | python scripts/notify.py -
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

TELEGRAM_DIR = Path.home() / ".claude" / "channels" / "telegram"
SEND_RETRIES = (0, 3, 10)   # seconds to wait before attempts 1, 2, 3
HTTP_TIMEOUT = 20
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) deadwire-notify/1.0"

_SECRETS: list[str] = []


def scrub(value: object) -> str:
    """Strip known secrets from anything on its way to the log."""
    text = str(value)
    for secret in _SECRETS:
        if secret:
            text = text.replace(secret, "<token>")
    return text


def telegram_config() -> tuple[str, str]:
    """Read the bot token and target chat. The token is never logged or printed."""
    token = ""
    for line in (TELEGRAM_DIR / ".env").read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("TELEGRAM_BOT_TOKEN="):
            token = stripped.split("=", 1)[1].strip().strip('"').strip("'")
    if token:
        _SECRETS.append(token)

    access = json.loads((TELEGRAM_DIR / "access.json").read_text(encoding="utf-8"))
    allowed = access.get("allowFrom") or []

    if not token:
        raise RuntimeError(f"no TELEGRAM_BOT_TOKEN in {TELEGRAM_DIR / '.env'}")
    if not allowed:
        raise RuntimeError(f"allowFrom is empty in {TELEGRAM_DIR / 'access.json'}")
    return token, str(allowed[0])


def send(text: str) -> bool:
    """Push to the phone. Returns False rather than raising, so a caller never dies here."""
    try:
        token, chat_id = telegram_config()
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"! telegram not usable: {scrub(exc)}", file=sys.stderr)
        return False

    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = json.dumps({
        "chat_id": chat_id,
        "text": text[:3900],
        "disable_web_page_preview": True,
    }).encode("utf-8")

    for attempt, pause in enumerate(SEND_RETRIES, start=1):
        if pause:
            time.sleep(pause)
        try:
            request = urllib.request.Request(
                url, data=payload,
                headers={"Content-Type": "application/json", "User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
                if json.loads(response.read().decode("utf-8")).get("ok"):
                    return True
            print(f"! telegram attempt {attempt}: api returned ok=false", file=sys.stderr)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            print(f"! telegram attempt {attempt}: {scrub(exc)}", file=sys.stderr)
    return False


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    text = sys.stdin.read() if args[0] == "-" else " ".join(args)
    if not text.strip():
        print("! nothing to send", file=sys.stderr)
        return 2
    return 0 if send(text) else 1


if __name__ == "__main__":
    raise SystemExit(main())
