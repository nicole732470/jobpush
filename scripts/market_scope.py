"""Conservative US/non-US classification for public ATS location strings."""

from __future__ import annotations

import re


US_STATES = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
    "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
    "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
    "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
    "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
    "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
    "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
    "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
    "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI",
    "south carolina": "SC", "south dakota": "SD", "tennessee": "TN", "texas": "TX",
    "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA",
    "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
    "district of columbia": "DC",
}
STATE_CODES = set(US_STATES.values())
NON_US_MARKERS = {
    "canada", "united kingdom", "uk", "england", "ireland", "germany", "france",
    "spain", "italy", "netherlands", "poland", "romania", "india", "china", "japan",
    "singapore", "australia", "mexico", "brazil", "colombia", "argentina", "israel",
    "sweden", "norway", "denmark", "finland", "switzerland", "austria", "belgium",
    "portugal", "czech", "hungary", "philippines", "vietnam", "indonesia", "malaysia",
}


def classify_market_scope(location: str | None, fallback: str = "unknown") -> str:
    value = re.sub(r"\s+", " ", location or "").strip()
    lowered = value.casefold()
    if not lowered:
        return fallback

    if re.search(r"\b(united states|u\.s\.|u\.s\.a\.|usa)\b", lowered):
        return "US"
    if any(re.search(rf"\b{re.escape(state)}\b", lowered) for state in US_STATES):
        return "US"
    if any(re.search(rf"(?:,|/| -)\s*{code}(?:\b|$)", value, re.IGNORECASE) for code in STATE_CODES):
        return "US"

    if any(re.search(rf"\b{re.escape(marker)}\b", lowered) for marker in NON_US_MARKERS):
        return "non-US"
    return fallback
