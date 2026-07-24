import json
from collections import defaultdict
from typing import Optional, Set

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: Set[WebSocket] = set()
        self._user_connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, websocket: WebSocket, user_id: str) -> None:
        await websocket.accept()
        self.active_connections.add(websocket)
        self._user_connections[user_id].add(websocket)

    def disconnect(self, websocket: WebSocket, user_id: Optional[str] = None) -> None:
        self.active_connections.discard(websocket)
        if user_id:
            user_set = self._user_connections.get(user_id)
            if user_set is not None:
                user_set.discard(websocket)
                if not user_set:
                    self._user_connections.pop(user_id, None)
            return

        stale_users: list[str] = []
        for uid, sockets in self._user_connections.items():
            sockets.discard(websocket)
            if not sockets:
                stale_users.append(uid)
        for uid in stale_users:
            self._user_connections.pop(uid, None)

    async def broadcast_json(self, message: dict) -> None:
        data = json.dumps(message)
        stale = []
        for connection in list(self.active_connections):
            try:
                await connection.send_text(data)
            except Exception:
                stale.append(connection)
        for conn in stale:
            self.disconnect(conn)

    async def broadcast_to_user(self, user_id: str, message: dict) -> int:
        sockets = list(self._user_connections.get(user_id, set()))
        if not sockets:
            return 0

        data = json.dumps(message)
        sent = 0
        stale: list[WebSocket] = []
        for connection in sockets:
            try:
                await connection.send_text(data)
                sent += 1
            except Exception:
                stale.append(connection)

        for connection in stale:
            self.disconnect(connection, user_id=user_id)

        return sent

    def get_status(self) -> dict:
        return {
            "active_connections": len(self.active_connections),
            "connected_users": len(self._user_connections),
        }


manager = ConnectionManager()
