"""Golden transcript diff — v1 事件流逐字节兼容回归护栏（arch-next-spec 测试决策 1）。

用法:
    python golden_check.py generate <cfg> <port> <ready_file>
        启动 mock server，跑一次 headless mp，将「归一化后的」transcript 事件流
        写入 testdata/golden_transcript.jsonl（作为 v1 行为基线夹具）。
    python golden_check.py check <cfg> <port> <ready_file>
        同上运行，归一化后与夹具逐字节比较；一致 exit 0，不一致打印 diff 后 exit 1。

归一化（把每次运行必然变化的字段替换为占位符，其余逐字节保真，含字段顺序）:
    timestamp -> "TS" / session_id -> "S" / turn_id -> "TURN" / request_id -> "REQ"
    latency_ms -> "L" / assembly.date -> "DATE" / cwd -> "CWD"
    parent_session_id / parent_request_id 统一为 "NULL"（无父会话时均为 null）
"""
import json
import os
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "golden_transcript.jsonl")

NORMALIZE_FIELDS = {
    "timestamp": "TS",
    "session_id": "S",
    "turn_id": "TURN",
    "request_id": "REQ",
    "latency_ms": "L",
    "cwd": "CWD",
    # system_prompt 含渲染后的 {{date}}/{{cwd}}（每日/每路径变化）；其装配正确性
    # 由 test_prompt_assembly 单测覆盖，golden diff 只护栏事件结构与顺序。
    "system_prompt": "SYS",
    "parent_session_id": "NULL",
    "parent_request_id": "NULL",
}


def normalize_event(line):
    event = json.loads(line)
    for key, placeholder in NORMALIZE_FIELDS.items():
        if key in event:
            event[key] = placeholder
    assembly = event.get("assembly")
    if isinstance(assembly, dict) and "date" in assembly:
        assembly["date"] = "DATE"
    return json.dumps(event, ensure_ascii=False, sort_keys=False)


def run_headless(cfg, port, ready_file):
    """启动 mock server + mp headless，返回归一化事件行列表。"""
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            try:
                req = json.loads(raw.decode("utf-8"))
            except Exception:
                req = {}
            msgs = req.get("messages", [])
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
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    with open(ready_file, "w", encoding="utf-8") as f:
        f.write("ready")

    try:
        subprocess.run(
            [
                os.path.join(HERE, "..", "build", "mp.exe"),
                "--headless",
                "--config",
                cfg,
                "--base-url",
                "http://127.0.0.1:%d" % port,
                "-t",
                "hello golden",
            ],
            check=True,
            timeout=60,
            capture_output=True,
        )
    finally:
        server.shutdown()

    tdir = os.path.join(cfg, "transcripts")
    files = [f for f in os.listdir(tdir) if f.endswith(".jsonl")]
    assert len(files) == 1, "expected exactly one transcript, got %r" % files
    with open(os.path.join(tdir, files[0]), encoding="utf-8") as f:
        return [normalize_event(line) for line in f if line.strip()]


def main():
    mode, cfg, port, ready_file = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    if os.path.exists(ready_file):
        os.remove(ready_file)
    lines = run_headless(cfg, port, ready_file)
    assert len(lines) >= 5, "expected >= 5 events, got %d" % len(lines)

    if mode == "generate":
        with open(FIXTURE, "w", encoding="utf-8") as f:
            for line in lines:
                f.write(line + "\n")
        print("golden fixture written: %d events" % len(lines))
        return

    with open(FIXTURE, encoding="utf-8") as f:
        expected = [line.rstrip("\n") for line in f if line.strip()]
    if lines == expected:
        print("golden diff OK: %d events byte-identical (normalized)" % len(lines))
        sys.exit(0)
    for i, (a, b) in enumerate(zip(lines, expected)):
        if a != b:
            print("FIRST DIFF at event #%d:\n  got:      %s\n  expected: %s" % (i, a, b))
            break
    print("event counts: got %d, expected %d" % (len(lines), len(expected)))
    sys.exit(1)


if __name__ == "__main__":
    main()
