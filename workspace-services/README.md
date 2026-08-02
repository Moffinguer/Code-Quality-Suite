# Servicios de apoyo (bundle portable)

Empaqueta la infraestructura que no es tu código: el **gateway de modelos**
(LiteLLM) y la **conversión de documentos a Markdown** (MarkItDown). Un clic para
levantarlo, y una CLI para hablar con ambos desde el terminal.

## Arranque

```bash
cp .env.example .env        # y pon tu ANTHROPIC_API_KEY
./svc up                    # construye y levanta todo
```

Quedan disponibles:
- Gateway de modelos: `http://localhost:4000/v1` (formato OpenAI)
- Conversor de documentos: `http://localhost:8080/convert`

## Uso desde la CLI

```bash
./svc convert contrato.pdf > docs/spec/contrato.md   # documento -> Markdown
./svc ask cheap "una pregunta rápida"                 # una sola pregunta
./svc chat strong                                     # chat interactivo (tipo CLI)
./svc logs                                            # ver logs
./svc down                                            # parar
```

### Chat interactivo

`./svc chat [modelo]` abre una sesión estilo REPL contra el gateway. Dentro:

```
> /file docs/spec/contrato.pdf     # convierte y adjunta el fichero al contexto
> ¿qué cláusulas hablan de plazos?
> /model cheap                     # cambia de modelo en caliente
> /system Eres un revisor de contratos conciso.
> /reset                           # borra el historial
> /exit
```

## Conectar los agentes

- **Modelos:** en Cline (u otro), añade un proveedor OpenAI-compatible apuntando a
  `http://localhost:4000/v1` con tu `LITELLM_MASTER_KEY`. Ahí eliges `strong`,
  `cheap`, `local` o `private`.
- **Conversión de documentos por el propio agente (opcional):** descomenta el
  servicio `converter-mcp` en `docker-compose.yml` y añádelo en Cline como MCP
  server (`http://localhost:3001/mcp`). Así el agente convierte documentos solo.

## Portabilidad

Todo son contenedores: copia esta carpeta a otra máquina, pon el `.env` y
`./svc up`. No necesitas instalar Python, MarkItDown ni LiteLLM en el host.

Ajusta los modelos en `litellm/config.yaml`. Para documentos con tablas/fórmulas
complejas, cambia el motor del conversor a Docling (más pesado, mejor fidelidad).
