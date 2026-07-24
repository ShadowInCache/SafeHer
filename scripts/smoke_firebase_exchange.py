"""Smoke test Firebase token exchange against SafeHer FastAPI backend.

Usage:
  python scripts/smoke_firebase_exchange.py --id-token <firebase_id_token>

Or set SAFEHER_FIREBASE_ID_TOKEN in environment.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import requests


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SafeHer Firebase exchange smoke test")
    parser.add_argument("--base-url", default="http://localhost:5000", help="SafeHer API base URL")
    parser.add_argument("--id-token", default=os.getenv("SAFEHER_FIREBASE_ID_TOKEN"), help="Firebase ID token")
    parser.add_argument("--role", default="user", help="Requested SafeHer role (user or guardian)")
    parser.add_argument("--full-name", default=None, help="Optional full name for first-time provisioning")
    parser.add_argument("--timeout", type=int, default=10, help="HTTP timeout seconds")
    return parser.parse_args()


def _print_json(label: str, payload: Any) -> None:
    print(label)
    print(payload)


def main() -> int:
    args = parse_args()
    if not args.id_token:
        print("Missing Firebase ID token.")
        print("Provide --id-token or set SAFEHER_FIREBASE_ID_TOKEN.")
        return 2

    base_url = args.base_url.rstrip("/")
    exchange_url = f"{base_url}/api/v1/auth/firebase/exchange"
    me_url = f"{base_url}/api/v1/auth/me"

    print(f"Exchange endpoint: {exchange_url}")
    exchange_payload = {
        "id_token": args.id_token,
        "role": args.role,
    }
    if args.full_name:
        exchange_payload["full_name"] = args.full_name

    try:
        exchange_response = requests.post(
            exchange_url,
            json=exchange_payload,
            timeout=args.timeout,
        )
    except requests.RequestException as exc:
        print(f"Exchange request failed: {exc}")
        return 3

    print(f"Exchange status: {exchange_response.status_code}")
    try:
        exchange_data = exchange_response.json()
    except ValueError:
        exchange_data = {"raw": exchange_response.text}

    _print_json("Exchange response:", exchange_data)

    if exchange_response.status_code != 200:
        print("Exchange did not succeed.")
        if exchange_response.status_code == 401:
            print("Hint: token may be expired/invalid or project ID mismatched.")
        return 4

    access_token = exchange_data.get("access_token")
    if not access_token:
        print("Exchange response missing access_token")
        return 5

    try:
        me_response = requests.get(
            me_url,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=args.timeout,
        )
    except requests.RequestException as exc:
        print(f"/auth/me request failed: {exc}")
        return 6

    print(f"/auth/me status: {me_response.status_code}")
    try:
        me_data = me_response.json()
    except ValueError:
        me_data = {"raw": me_response.text}

    _print_json("/auth/me response:", me_data)

    if me_response.status_code != 200:
        return 7

    print("Firebase exchange smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
