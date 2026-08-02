# syntax=docker/dockerfile:1
FROM python:3.12-slim
RUN pip install --no-cache-dir \
      "markitdown[pdf,docx,pptx,xlsx]" markitdown-mcp \
      fastapi "uvicorn[standard]" python-multipart
WORKDIR /app
COPY app.py .
RUN useradd -m app && chown -R app /app
USER app
EXPOSE 8080
# Por defecto: API REST para la CLI. El servicio MCP (opcional) se activa en compose.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
