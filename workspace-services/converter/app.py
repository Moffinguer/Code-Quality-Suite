"""Servicio minimo de conversion de documentos a Markdown (MarkItDown)."""
import os
import tempfile
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import PlainTextResponse
from markitdown import MarkItDown

app = FastAPI(title="doc-converter")
_md = MarkItDown()


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/convert", response_class=PlainTextResponse)
async def convert(file: UploadFile = File(...)):
    suffix = os.path.splitext(file.filename or "")[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        path = tmp.name
    try:
        return _md.convert(path).text_content
    finally:
        os.unlink(path)
