#!/usr/bin/env python3
"""Spider-Man showtime checker for PVR Icon, Phoenix Palladium, Lower Parel, Mumbai."""

import urllib.request
import urllib.error
import json
import sys
from datetime import datetime, timezone, timedelta

IST = timezone(timedelta(hours=5, minutes=30))
URL = "https://in.bookmyshow.com/cinemas/MUMBAI/pvr-icon-phoenix-palladium-lower-parel-mumbai/buytickets/PIPP/20260730"
API_URL = "https://in.bookmyshow.com/serv/getData?cmd=GETSESSIONSBYVENUE&alt=json&venueCode=PIPP&date=20260730&pageCount=1&pageNo=1"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Accept": "application/json, text/html,*/*",
    "Accept-Language": "en-IN,en;q=0.9",
    "Referer": "https://in.bookmyshow.com/",
}


def fetch(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def check_showtimes():
    now = datetime.now(IST)
    results = []

    # Try API endpoint first
    try:
        data = fetch(API_URL)
        parsed = json.loads(data)
        sessions = parsed.get("SessionsByVenue", {}).get("BookingSessionDetails", [])
        if sessions:
            for s in sessions[:5]:
                time_ = s.get("Etime", s.get("ShowTime", ""))
                lang = s.get("Dim", "")
                avail = s.get("Status", "")
                results.append(f"{time_} {lang} [{avail}]")
    except Exception:
        pass

    # Try main page as fallback
    if not results:
        try:
            html = fetch(URL)
            if "spider" in html.lower() or "PIPP" in html:
                # Look for time patterns
                import re
                times = re.findall(r'\b(1[0-2]|0?[1-9]):[0-5]\d\s*[APap][Mm]\b', html)
                if times:
                    results = list(dict.fromkeys(times))[:6]
        except Exception as e:
            return None, str(e)

    return results, None


def main():
    now = datetime.now(IST)
    times_found, error = check_showtimes()

    if error and not times_found:
        status = f"FETCH ERROR: {error[:80]}"
    elif times_found:
        status = "AVAILABLE: " + ", ".join(times_found)
    else:
        status = "NOT AVAILABLE YET"

    print(f"[{now.strftime('%H:%M IST')}] Spider-Man @ PVR Palladium - {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
