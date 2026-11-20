import { createHash } from "node:crypto";
import type { WebSocket } from "ws";
import type Database from "better-sqlite3";

const rooms = new Map<string, Set<WebSocket>>();

export function resolveToken(
  db: Database.Database,
  bearerToken: string,
): { accountId: string } | null {
  const hash = createHash("sha256").update(bearerToken).digest("hex");
  const row = db
    .prepare("SELECT account_id FROM tokens WHERE token_hash = ? AND revoked = 0")
    .get(hash) as { account_id: string } | undefined;
  if (!row) return null;
  return { accountId: row.account_id };
}

export function addSocket(accountId: string, ws: WebSocket): void {
  let room = rooms.get(accountId);
  if (!room) {
    room = new Set();
    rooms.set(accountId, room);
  }
  room.add(ws);

  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.t === "ping") {
        ws.send(JSON.stringify({ t: "pong" }));
      }
    } catch {}
  });

  ws.on("close", () => {
    const r = rooms.get(accountId);
    if (r) {
      r.delete(ws);
      if (r.size === 0) rooms.delete(accountId);
    }
  });

  ws.on("error", () => {
    ws.close();
  });
}

export function broadcast(accountId: string): void {
  const room = rooms.get(accountId);
  if (!room) return;
  const msg = JSON.stringify({ t: "wake" });
  for (const ws of room) {
    try {
      ws.send(msg);
    } catch {}
  }
}
