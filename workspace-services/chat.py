#!/usr/bin/env python3
"""Cliente de chat minimo contra el gateway svc (LiteLLM), con adjunto de ficheros.

Comandos dentro del chat:
  /file <ruta>   convierte el fichero a Markdown (via el conversor) y lo adjunta
  /model <n>     cambia de modelo (strong, cheap, local, private)
  /system <txt>  fija el mensaje de sistema
  /reset         borra el historial
  /exit          salir
"""
import json
import os
import sys
import urllib.request
import urllib.error

LITELLM = os.environ.get("LITELLM_URL", "http://localhost:4000/v1")
CONVERTER = os.environ.get("CONVERTER_URL", "http://localhost:8080")
KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-local-master")


def post_json(url, payload, headers=None):
    data = json.dumps(payload).encode()
    hdr = {"Content-Type": "application/json"}
    hdr.update(headers or {})
    req = urllib.request.Request(url, data=data, method="POST", headers=hdr)
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def convert_file(path):
    boundary = "----svcchatboundary"
    fname = os.path.basename(path)
    with open(path, "rb") as f:
        body = f.read()
    pre = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{fname}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    post = f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        f"{CONVERTER}/convert", data=pre + body + post, method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode("utf-8", "replace")


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CHAT_MODEL", "cheap")
    messages = []
    print(f"svc chat — modelo: {model}")
    print("Comandos: /file <ruta>  /model <n>  /system <txt>  /reset  /exit")
    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        if line == "/exit":
            break
        if line == "/reset":
            messages = []
            print("(historial borrado)")
            continue
        if line.startswith("/model "):
            model = line[7:].strip()
            print(f"(modelo: {model})")
            continue
        if line.startswith("/system "):
            messages = [m for m in messages if m["role"] != "system"]
            messages.insert(0, {"role": "system", "content": line[8:].strip()})
            print("(system fijado)")
            continue
        if line.startswith("/file "):
            path = line[6:].strip()
            try:
                content = convert_file(path)
            except Exception as exc:
                try:
                    content = open(path, encoding="utf-8", errors="replace").read()
                    print(f"(conversor no disponible, leído como texto: {exc})")
                except Exception as exc2:
                    print(f"(no se pudo leer: {exc2})")
                    continue
            messages.append({
                "role": "user",
                "content": f"Adjunto el fichero {os.path.basename(path)}:\n\n{content}",
            })
            print(f"(adjuntado {os.path.basename(path)}: {len(content)} chars — escribe tu pregunta)")
            continue

        messages.append({"role": "user", "content": line})
        try:
            resp = post_json(
                f"{LITELLM}/chat/completions",
                {"model": model, "messages": messages},
                {"Authorization": f"Bearer {KEY}"},
            )
            reply = resp["choices"][0]["message"]["content"]
        except urllib.error.URLError as exc:
            print(f"(error de conexión: {exc}. ¿Has hecho ./svc up?)")
            messages.pop()
            continue
        except Exception as exc:
            print(f"(error: {exc})")
            messages.pop()
            continue
        messages.append({"role": "assistant", "content": reply})
        print(reply)


if __name__ == "__main__":
    main()
