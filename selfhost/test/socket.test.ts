import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { WebSocket, WebSocketServer } from "ws";
import Database from "better-sqlite3";
import * as workerModule from "../../worker/src/index";
import { makeEnv } from "../src/adapters/env";
import { addSocket, broadcast, resolveToken } from "../src/sockets";

function pickHandler(m: any): any {
  let cur = m;
  for (let i = 0; i < 6 && cur; i++) {
    if (typeof cur.fetch === "function") return cur;
    cur = cur.default;
  }
  throw new Error("worker handler with fetch() not found");
}
const worker: any = pickHandler(workerModule);

async function run() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "relic-ws-test-"));
  const db = new Database(path.join(tmp, "relic.db"));
  const schemaSql = fs.readFileSync(path.resolve("src/../../worker/schema.sql"), "utf8");
  db.exec(schemaSql);

  const token = "test-token-ws";
  const { createHash } = await import("node:crypto");
  const hash = createHash("sha256").update(token).digest("hex");
  db.prepare("INSERT INTO tokens (token_hash, account_id, tier) VALUES (?, ?, 'max')").run(hash, "acc-1");

  const env = makeEnv(db, path.join(tmp, "blobs"));

  const server = http.createServer(async (req, res) => {
    const url = new URL("http://localhost" + (req.url || "/"));
    let body: Buffer | undefined;
    if (req.method !== "GET" && req.method !== "HEAD") {
      const chunks: Buffer[] = [];
      for await (const c of req) chunks.push(c as Buffer);
      if (chunks.length) body = Buffer.concat(chunks);
    }
    const headers = new Headers();
    for (const [k, v] of Object.entries(req.headers)) {
      if (v) headers.set(k, Array.isArray(v) ? v.join(",") : v);
    }
    const request = new Request(url.toString(), {
      method: req.method,
      headers,
      body: body && body.length ? body : undefined,
    });

    const response = await worker.fetch(request, env);
    if (response.status >= 200 && response.status < 300) {
      if (req.method === "PUT" && url.pathname.startsWith("/relic/")) {
        const auth = req.headers["authorization"];
        if (auth && auth.startsWith("Bearer ")) {
          const resolved = resolveToken(db, auth.slice(7));
          if (resolved) broadcast(resolved.accountId);
        }
      }
    }
    res.statusCode = response.status;
    res.end(await response.text());
  });

  const wss = new WebSocketServer({ noServer: true });
  server.on("upgrade", (req, socket, head) => {
    const url = new URL("http://localhost" + (req.url || "/"));
    if (url.pathname !== "/sync/socket") {
      socket.destroy();
      return;
    }
    const auth = req.headers["authorization"];
    if (!auth || !auth.startsWith("Bearer ")) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }
    const resolved = resolveToken(db, auth.slice(7));
    if (!resolved) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      addSocket(resolved.accountId, ws);
    });
  });

  await new Promise<void>((resolve) => server.listen(0, resolve));
  const port = (server.address() as any).port;

  const ws = new WebSocket(`ws://localhost:${port}/sync/socket`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  await new Promise<void>((resolve, reject) => {
    ws.on("open", resolve);
    ws.on("error", reject);
  });
  console.log("  ok - websocket connected successfully");

  const wakePromise = new Promise<string>((resolve) => {
    ws.on("message", (data) => resolve(data.toString()));
  });

  const putRes = await fetch(`http://localhost:${port}/relic/item-123`, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      v: 1,
      uid: "item-123",
      created_at: 1000,
      updated_at: 1000,
      byte_size: 10,
      promoted: false,
      n: "nonce",
      ct: "ciphertext",
    }),
  });
  if (putRes.status !== 200) throw new Error(`PUT failed: ${putRes.status}`);

  const wakeMsg = await wakePromise;
  if (JSON.parse(wakeMsg).t !== "wake") throw new Error(`Unexpected message: ${wakeMsg}`);
  console.log("  ok - wake broadcast received over websocket");

  const pongPromise = new Promise<string>((resolve) => {
    ws.once("message", (data) => resolve(data.toString()));
  });
  ws.send(JSON.stringify({ t: "ping" }));
  const pongMsg = await pongPromise;
  if (JSON.parse(pongMsg).t !== "pong") throw new Error(`Unexpected pong: ${pongMsg}`);
  console.log("  ok - ping/pong keepalive works");

  ws.close();
  server.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log("WEBSOCKET TEST PASSED");
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
