#!/usr/bin/env node
// Send a WhatsApp message through the running whatsapp-channel plugin, without
// Claude: connects to the plugin's local IPC socket the way a second Claude
// terminal would, authenticates with its token file and calls the `reply` tool.
//   whatsapp-send.mjs <chat_id> <text>
// Exits 0 once the plugin reports the message sent, 1 otherwise (reason on
// stderr). Works while Claude itself is signed out, as long as the plugin runs.
import { readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { homedir } from "node:os";
import { join } from "node:path";

const [chatId, text] = process.argv.slice(2);
if (!chatId || !text) {
  console.error("usage: whatsapp-send.mjs <chat_id> <text>");
  process.exit(1);
}

const stateDir = process.env.WHATSAPP_STATE_DIR || join(homedir(), ".whatsapp-channel");
let token;
try {
  token = readFileSync(join(stateDir, ".ipc-token"), "utf8").trim();
} catch {
  console.error("whatsapp-send: no IPC token; is the WhatsApp plugin running?");
  process.exit(1);
}

const fail = (why) => {
  console.error(`whatsapp-send: ${why}`);
  process.exit(1);
};
setTimeout(() => fail("timed out"), 20_000).unref();

const socket = createConnection(join(stateDir, ".server.sock"));
socket.setEncoding("utf8");
socket.on("error", (err) => fail(`can't reach the plugin (${err.code ?? err.message})`));
socket.on("close", () => fail("the plugin closed the connection"));

let buf = "";
socket.on("data", (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf("\n")) !== -1) {
    const line = buf.slice(0, nl);
    buf = buf.slice(nl + 1);
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.type !== "result") continue; // ignore inbound-message notifies
    if (msg.id === "hello") {
      const call = { type: "call", id: "send", name: "reply", args: { chat_id: chatId, text } };
      socket.write(JSON.stringify(call) + "\n");
    } else if (msg.id === "send") {
      const res = msg.result ?? {};
      if (res.isError) {
        const detail = (res.content ?? []).map((c) => c.text).join(" ");
        fail(`send failed: ${detail}`);
      }
      process.exit(0);
    }
  }
});
socket.on("connect", () => socket.write(JSON.stringify({ type: "hello", token }) + "\n"));
