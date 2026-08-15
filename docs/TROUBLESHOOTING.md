# Resolución de problemas (casos reales resueltos)

Recopilación de los problemas encontrados durante la puesta en marcha y su
solución, para que el proyecto se despliegue y use sin sorpresas.

## Instalación / Windows

- **`execvpe(/bin/bash) failed` al lanzar `bootstrap.bat`** — el PATH tiene el
  stub de WSL (`System32\bash.exe`) sin distro. Los lanzadores actuales priorizan
  Git Bash e ignoran ese stub. Alternativa: abre **Git Bash** y usa `./bootstrap.sh`.
- **`svc: aider: not found` o "necesita un programa para abrir"** — en Windows
  ejecuta con `bash svc ...` (no `./svc`).
- **`Python was not found` / `python3` no existe** — en Windows el binario es
  `python`, no `python3`. El `svc` detecta el que exista. Si un alias de la
  Microsoft Store interfiere, desactívalo en *Configuración → Apps → Alias de
  ejecución de aplicaciones*.
- **`ModuleNotFoundError: psycopg`** (en `svc db-load`) — instala una vez:
  `python -m pip install "psycopg[binary]" pyyaml`.
- **Aider no instala en Windows/Python 3.13** (baja `aider-chat 0.16` y falla al
  compilar `libcst`/Rust) — usa el instalador aislado: `pip install aider-install`
  y luego `aider-install`; o `uv tool install --python 3.12 aider-chat`.

## Docker / build

- **Build falla: `can't find Rust compiler` (libcst)** — algún paquete pip
  (`ssort`, `teyit`, `pybetter`) arrastra `libcst`, que necesita Rust. Solución:
  usar el set reducido `sqlfluff black autopep8 isort pylint mypy` (ya aplicado).
- **CRLF en scripts de shell** — los `.sh`/hooks editados en Windows con CRLF
  rompen dentro del contenedor Linux. El `.gitattributes` fuerza LF; si editas a
  mano, guarda en LF. (Todos los scripts del repo están normalizados a LF.)
- **Imagen sobrecargada** — la imagen es MODULAR: solo instala las herramientas de
  los lenguajes detectados (`ENABLE_*`). Proyecto vacío = base mínima.

## Gateway LiteLLM / modelos

- **`401 No api key passed`** en `/v1/models` — añade
  `-H "Authorization: Bearer sk-local-master"` (el `svc ask/chat` ya la manda).
- **`Invalid model name` / modelo no encontrado** — tras `db-load` los alias
  cambian a los de la BD (`auto`, `architect`, `backend`...). Mira los reales con
  `curl .../v1/models -H "Authorization: Bearer sk-local-master"`. En **Aider** el
  modelo debe llevar prefijo Y existir: `openai/auto` (no `auto` a secas, ni
  `openai/architect` si ese alias no está cargado).
- **Gemini `no longer available to new users`** — usa `gemini/gemini-flash-latest`
  (alias siempre vigente) o un flash concreto de tu `/v1beta/models`.
- **429 / rate-limit** — límite del tier gratis (por minuto o por día, por modelo).
  Apila varios modelos del mismo proveedor (cada uno con su cupo) + `cooldown` en
  LiteLLM, que aparta el agotado. Groq tiene un tope de 12k tokens/min que el
  trabajo agéntico supera. Sin techo real: Ollama local o de pago.
- **Slug `:free` da 404** (p. ej. `qwen/qwen3-coder:free`) — los catálogos gratis
  rotan; verifica el id en la web del proveedor.
- **Config antigua tras actualizar** — al descomprimir un zip nuevo en Windows,
  algunos descompresores NO sobrescriben; extrae reemplazando. Tras cambiar la
  config: `./svc down && ./svc up`.

## Costes

- **¿Gasto dinero?** Con claves de free tier (Groq, Gemini, OpenRouter, Cerebras)
  y DeepSeek **sin método de pago**, es imposible incurrir en cargos: los free
  tiers fallan con 429 al agotarse (no cobran) y DeepSeek sin saldo/tarjeta
  simplemente deja de responder. Solo hay gasto si añades saldo/tarjeta a un
  proveedor de pago y una petición cae en su modelo.

## Lección transversal (agentes que editan código)

Cuando un agente (Aider/Cline) reescribe ficheros: **revisa siempre el diff**.
En este proyecto un agente borró comentarios y notas de seguridad, subió la
versión sin permiso y añadió dependencias frágiles que rompieron el build.
Pídele cambios mínimos ("no reformatees ni borres comentarios") y deja que el
**pre-push/CI con `docker build`** atrape estos fallos antes de integrarlos.
