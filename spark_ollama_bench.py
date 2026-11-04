#!/usr/bin/env python3
"""DGX Spark (Ollama) API testi: tok/s o'lchash.

Ishlatish:
  python3 spark_ollama_bench.py --list
  python3 spark_ollama_bench.py -m huihui_ai/gpt-oss-abliterated:120b -n 128
  python3 spark_ollama_bench.py -m qwen3.5:122b-a10b -p "Salom, o'zingni tanishtir" -n 200
"""
import argparse
import json
import time
import urllib.request

DEFAULT_BASE = "http://100.120.238.79:11434"


def post(base, path, payload, timeout=600):
    req = urllib.request.Request(
        base + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def get(base, path, timeout=30):
    with urllib.request.urlopen(base + path, timeout=timeout) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-b", "--base", default=DEFAULT_BASE, help="Ollama base URL")
    ap.add_argument("-m", "--model", default="huihui_ai/gpt-oss-abliterated:120b")
    ap.add_argument("-p", "--prompt", default="Write a short paragraph about local AI.")
    ap.add_argument("-n", "--num-predict", type=int, default=128)
    ap.add_argument("--keep-alive", default="5m")
    ap.add_argument("--list", action="store_true", help="Modellar ro'yxati")
    args = ap.parse_args()

    if args.list:
        data = get(args.base, "/api/tags")
        for m in sorted(data["models"], key=lambda x: -x["size"]):
            print(f"{m['name']:45s} {m['size'] / 1e9:7.1f} GB")
        return

    t0 = time.time()
    d = post(args.base, "/api/generate", {
        "model": args.model,
        "prompt": args.prompt,
        "stream": False,
        "keep_alive": args.keep_alive,
        "options": {"num_predict": args.num_predict, "temperature": 0},
    })

    load_s = d.get("load_duration", 0) / 1e9
    prompt_tps = d.get("prompt_eval_count", 0) / (d.get("prompt_eval_duration", 1) / 1e9)
    gen_tps = d.get("eval_count", 0) / (d.get("eval_duration", 1) / 1e9)

    print(f"model      : {args.model}")
    print(f"load       : {load_s:.1f} s")
    print(f"prompt     : {d.get('prompt_eval_count', 0)} tok @ {prompt_tps:.1f} tok/s")
    print(f"generate   : {d.get('eval_count', 0)} tok @ {gen_tps:.1f} tok/s")
    print(f"total      : {d.get('total_duration', 0) / 1e9:.1f} s")
    print(f"wall clock : {time.time() - t0:.1f} s")
    print("--- javob ---")
    print(d.get("response", "").strip()[:1000])


if __name__ == "__main__":
    main()
