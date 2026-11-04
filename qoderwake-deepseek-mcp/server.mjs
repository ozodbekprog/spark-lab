#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const VERSION = "1.0.0";
const ENV_FILE = join(homedir(), ".qoderwake", "deepseek.env");

function readEnvFile() {
  try {
    const out = {};
    for (const line of readFileSync(ENV_FILE, "utf8").split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
      if (!m) continue;
      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.slice(1, -1);
      }
      out[m[1]] = v;
    }
    return out;
  } catch {
    return {};
  }
}

function getConfig() {
  const file = readEnvFile();
  return {
    apiKey: process.env.DEEPSEEK_API_KEY || file.DEEPSEEK_API_KEY || "",
    baseUrl: (process.env.DEEPSEEK_BASE_URL || file.DEEPSEEK_BASE_URL || "https://api.deepseek.com").replace(/\/+$/, ""),
    defaultModel: process.env.DEEPSEEK_MODEL || file.DEEPSEEK_MODEL || "deepseek-chat",
  };
}

const TOOL = {
  name: "deepseek_chat",
  description:
    "Send a prompt to DeepSeek's API and return its answer. Use it for a second opinion, drafts, translations, summaries, or any subtask you want DeepSeek to handle.",
  inputSchema: {
    type: "object",
    properties: {
      prompt: { type: "string", description: "User message to send to DeepSeek." },
      system: { type: "string", description: "Optional system prompt." },
      model: {
        type: "string",
        enum: ["deepseek-chat", "deepseek-reasoner"],
        description: "DeepSeek model. Defaults to deepseek-chat.",
      },
      temperature: { type: "number", minimum: 0, maximum: 2 },
      max_tokens: { type: "integer", minimum: 1 },
    },
    required: ["prompt"],
    additionalProperties: false,
  },
};

async function deepseekChat(args) {
  const { apiKey, baseUrl, defaultModel } = getConfig();
  if (!apiKey) {
    return {
      content: [
        {
          type: "text",
          text: `DeepSeek API key topilmadi. ${ENV_FILE} fayliga DEEPSEEK_API_KEY=... yozing yoki DEEPSEEK_API_KEY env o'zgaruvchisini o'rnating.`,
        },
      ],
      isError: true,
    };
  }

  const model = args.model || defaultModel;
  const messages = [];
  if (args.system) messages.push({ role: "system", content: String(args.system) });
  messages.push({ role: "user", content: String(args.prompt) });

  const body = { model, messages, stream: false };
  if (typeof args.temperature === "number") body.temperature = args.temperature;
  if (Number.isInteger(args.max_tokens)) body.max_tokens = args.max_tokens;

  let res;
  try {
    res = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(180000),
    });
  } catch (err) {
    return {
      content: [{ type: "text", text: `DeepSeek API'ga ulanib bo'lmadi: ${err.message}` }],
      isError: true,
    };
  }

  const raw = await res.text();
  if (!res.ok) {
    let detail = raw.slice(0, 500);
    try {
      detail = JSON.parse(raw)?.error?.message || detail;
    } catch {}
    return {
      content: [{ type: "text", text: `DeepSeek API xatosi (HTTP ${res.status}): ${detail}` }],
      isError: true,
    };
  }

  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    return { content: [{ type: "text", text: "DeepSeek javobini o'qib bo'lmadi." }], isError: true };
  }

  const msg = data?.choices?.[0]?.message || {};
  let out = msg.content || "";
  if (msg.reasoning_content) {
    out = `[reasoning]\n${msg.reasoning_content}\n\n[answer]\n${out}`;
  }
  if (!out) out = "(DeepSeek bo'sh javob qaytardi)";

  const meta = [`model: ${data.model || model}`];
  if (data.usage) meta.push(`tokens: ${data.usage.prompt_tokens}+${data.usage.completion_tokens}`);
  return { content: [{ type: "text", text: `${out}\n\n---\n${meta.join("; ")}` }] };
}

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

async function handleMessage(msg) {
  const { id, method, params } = msg;
  if (method === undefined || id === undefined) return;

  if (method === "initialize") {
    send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: params?.protocolVersion || "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: { name: "qoderwake-deepseek", version: VERSION },
      },
    });
    return;
  }
  if (method === "ping") {
    send({ jsonrpc: "2.0", id, result: {} });
    return;
  }
  if (method === "tools/list") {
    send({ jsonrpc: "2.0", id, result: { tools: [TOOL] } });
    return;
  }
  if (method === "tools/call") {
    if (params?.name !== TOOL.name) {
      send({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: `Unknown tool: ${params?.name}` }], isError: true },
      });
      return;
    }
    try {
      send({ jsonrpc: "2.0", id, result: await deepseekChat(params.arguments || {}) });
    } catch (err) {
      send({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: `Internal error: ${err.message}` }], isError: true },
      });
    }
    return;
  }
  send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
}

let buffer = "";
const pending = new Set();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    const task = handleMessage(msg);
    pending.add(task);
    task.finally(() => pending.delete(task));
  }
});

process.stdin.on("end", async () => {
  await Promise.allSettled([...pending]);
  process.exit(0);
});
