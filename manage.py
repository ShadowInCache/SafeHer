#!/usr/bin/env python3
"""SafeHer service manager for FastAPI + Docker services."""

from __future__ import annotations

import argparse
import logging
import shutil
import subprocess
import sys
from pathlib import Path

import requests


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


class SafeHerManager:
    def __init__(self) -> None:
        self.project_root = Path(__file__).resolve().parent
        self.compose_dir = self.project_root / "deployment" / "docker"
        self.compose_file = self.compose_dir / "docker-compose.yml"

    def _compose_base(self) -> list[str]:
        if shutil.which("docker"):
            return ["docker", "compose", "-f", str(self.compose_file)]
        if shutil.which("docker-compose"):
            return ["docker-compose", "-f", str(self.compose_file)]
        raise RuntimeError("Docker Compose not found. Install Docker Desktop.")

    def _run(self, args: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(args, cwd=cwd, check=check)

    def start_services(self) -> bool:
        try:
            cmd = [*self._compose_base(), "up", "-d"]
            self._run(cmd, cwd=self.compose_dir)
            logger.info("Docker services started")
            return True
        except Exception as exc:
            logger.error("Failed to start services: %s", exc)
            return False

    def stop_services(self) -> bool:
        try:
            cmd = [*self._compose_base(), "down"]
            self._run(cmd, cwd=self.compose_dir)
            logger.info("Docker services stopped")
            return True
        except Exception as exc:
            logger.error("Failed to stop services: %s", exc)
            return False

    def restart_services(self) -> bool:
        return self.stop_services() and self.start_services()

    def status(self) -> bool:
        ok = True
        try:
            cmd = [*self._compose_base(), "ps"]
            self._run(cmd, cwd=self.compose_dir, check=False)
        except Exception as exc:
            logger.error("Failed to inspect Docker status: %s", exc)
            ok = False

        for label, url in (
            ("API", "http://localhost:5000/api/v1/health"),
            ("Processor", "http://localhost:8080/health"),
        ):
            try:
                response = requests.get(url, timeout=2)
                if response.ok:
                    logger.info("%s healthy at %s", label, url)
                else:
                    ok = False
                    logger.warning("%s returned status %s", label, response.status_code)
            except Exception:
                ok = False
                logger.warning("%s unreachable at %s", label, url)

        return ok

    def start_api(self, host: str = "0.0.0.0", port: int = 5000) -> bool:
        logger.info("Starting FastAPI backend on http://%s:%s", host, port)
        cmd = [
            sys.executable,
            "-m",
            "uvicorn",
            "fastapi_app.main:app",
            "--host",
            host,
            "--port",
            str(port),
        ]
        result = self._run(cmd, cwd=self.project_root, check=False)
        return result.returncode == 0

    def start_all(self, host: str = "0.0.0.0", port: int = 5000) -> bool:
        if not self.start_services():
            return False
        return self.start_api(host=host, port=port)

    def logs(self, service: str) -> bool:
        service_map = {
            "redis": "redis",
            "mqtt": "mqtt",
            "processor": "safeher_processor",
        }
        target = service_map.get(service, service)
        try:
            cmd = [*self._compose_base(), "logs", "-f", target]
            self._run(cmd, cwd=self.compose_dir, check=False)
            return True
        except Exception as exc:
            logger.error("Failed to stream logs: %s", exc)
            return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SafeHer Integration Manager")
    parser.add_argument(
        "command",
        choices=[
            "status",
            "start",
            "start-api",
            "start-gateway",
            "start-all",
            "stop",
            "restart",
            "logs",
        ],
        help="Command to execute",
    )
    parser.add_argument("--service", choices=["redis", "mqtt", "processor"], default="processor")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5000)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manager = SafeHerManager()

    if args.command == "status":
        return 0 if manager.status() else 1
    if args.command == "start":
        return 0 if manager.start_services() else 1
    if args.command in {"start-api", "start-gateway"}:
        return 0 if manager.start_api(host=args.host, port=args.port) else 1
    if args.command == "start-all":
        return 0 if manager.start_all(host=args.host, port=args.port) else 1
    if args.command == "stop":
        return 0 if manager.stop_services() else 1
    if args.command == "restart":
        return 0 if manager.restart_services() else 1
    if args.command == "logs":
        return 0 if manager.logs(args.service) else 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
