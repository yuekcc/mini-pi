#!/usr/bin/env python3
"""Mock OpenAI-compatible /chat/completions SSE server for transcript integration tests.

Usage: python mock_openai_server.py <port> <ready_file> <request_log_file> [delay_ms]

- POST /chat/completions: logs the request body (one JSON per line) to request_log_file,
  then responds with an SSE stream: one content chunk + a final chunk carrying
  finish_reason="stop" and a fixed usage block.
- The content echoes the number of received messages, e.g. "mock reply: received 4 messages",
  so tests can verify resume reconstruction end-to-end (the rebuilt history is visible
  to the "model" as the message count).
- delay_ms (optional): sleeps before responding — used by interrupt tests to hold the
  request open long enough for Ctrl+C injection.
- Writes <ready_file> once the server is listening (polled by the test).
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def main():
    port = int(sys.argv[1])
    ready_file = sys.argv[2]
    request_log = sys.argv[3]
    delay_ms = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            try:
                req = json.loads(raw.decode("utf-8"))
            except Exception:
                req = {}
            with open(request_log, "a", encoding="utf-8") as f:
                f.write(json.dumps(req, ensure_ascii=False) + "\n")

            if delay_ms > 0:
                time.sleep(delay_ms / 1000.0)

            msgs = req.get("messages", [])

            # 特殊任务 "TOOLCALL"：回复一个 Bash tool_call（sleep 60），供 L2 工具中断测试。
            last_user = ""
            for m in msgs:
                if m.get("role") == "user":
                    last_user = m.get("content", "")
            if "TOOLCALL" in last_user:
                sse = (
                    'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_long1",'
                    '"type":"function","function":{"name":"Bash",'
                    '"arguments":"{\\"command\\":\\"sleep 60\\"}"}}]},'
                    '"index":0}]}\n\n'
                    'data: {"choices":[{"delta":{},"index":0,"finish_reason":"tool_calls"}],'
                    '"usage":{"prompt_tokens":11,"completion_tokens":7,"reasoning_tokens":3}}\n\n'
                    "data: [DONE]\n\n"
                )
            else:
                content = "mock reply: received %d messages" % len(msgs)
                sse = (
                    'data: {"choices":[{"delta":{"role":"assistant","content":"%s"},"index":0}]}\n\n'
                    'data: {"choices":[{"delta":{},"index":0,"finish_reason":"stop"}],'
                    '"usage":{"prompt_tokens":11,"completion_tokens":7,"reasoning_tokens":3}}\n\n'
                    "data: [DONE]\n\n"
                ) % content
            payload = sse.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", port), Handler)
    with open(ready_file, "w", encoding="utf-8") as f:
        f.write("ready")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
