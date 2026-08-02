# Guía de instalación, configuración y uso

Sistema completo de desarrollo asistido por IA con control de calidad. Se compone
de **cuatro capas** que funcionan juntas; cada una aporta valor por sí sola, así
que puedes montarlas de forma incremental.

1. **Gate de calidad** — hooks + CI. De lo que no se escapa ningún código.
2. **Memoria compartida** — `AGENTS.md` + especificación. Donde vive el contexto.
3. **Agentes de IA** — gateway de modelos (LiteLLM) + orquestador (Cline).
4. **Apoyo** — conversión de documentos a Markdown y chat por CLI.

**Orden recomendado de implementación:** 1 → CI → 2 → 3 → 4. No necesitas todo el
primer día.

---

## Herramientas usadas (resumen)

| Área | Herramientas |
|------|--------------|
| Formato/análisis Java | google-java-format, Checkstyle, PMD |
| Formato/análisis web | Prettier, ESLint (+typescript-eslint, plugin-html), Stylelint, html-validate |
| Markdown / XML / Docker | markdownlint-cli2, xmllint, hadolint |
| Contenedor base | Docker, JDK 21 (Temurin), Node 20 |
| Mensajes de commit | Conventional Commits (hooks commit-msg / prepare-commit-msg) |
| Gateway de modelos | LiteLLM |
| Modelos (gratis) | Groq, OpenRouter, Google AI Studio (Gemini), Ollama (local) |
| Modelos (de pago) | DeepSeek, Anthropic… (cualquiera compatible) |
| Orquestador / agente | Cline (o Kilo Code); estándar AGENTS.md |
| Conversión de documentos | MarkItDown (Docling para casos complejos) |
| Routing por dificultad (opcional) | RouteLLM o tags de LiteLLM |

---

## Requisitos

- Docker y Git en cada máquina.
- Para la capa de agentes: VS Code (para Cline) y una key de algún proveedor.
- Opcional: Ollama (modelos locales), Python 3 (para el chat por CLI).

---

## Capa 1 — Gate de calidad

Lo primero y más importante. Da igual quién programe: si no pasa, no entra.

### Instalación (multiplataforma)

```bash
# Linux / macOS:
./bootstrap.sh https://github.com/spring-projects/spring-petclinic.git

# Windows (cmd):        bootstrap.bat <git-url|ruta> [destino]
# Windows (PowerShell): .\bootstrap.ps1 <git-url|ruta> [destino]
# macOS (doble clic):   bootstrap.command
```

Clona, detecta la versión de Java, gestiona `.gitattributes`, construye la imagen
e instala los hooks (`pre-commit`, `pre-push`, `commit-msg`, `prepare-commit-msg`).
Ajusta parámetros en `.git/hooks/quality-suite.env`.

### Qué se comprueba

Java, Markdown, XML, Dockerfile, HTML/XHTML, JS/TS, CSS/SCSS (incluido el
JS/CSS embebido en HTML) y JSP. Ver la tabla completa en el README.

### Qué pasa en cada momento

- **Commit** → formatea y analiza el staging; bloquea si hay violaciones.
- **Push** → verifica el rango en modo check + etapa pesada opcional
  (`QUALITY_HEAVY_CMD="mvn -B verify"` para SpotBugs, cobertura, `tsc --noEmit`…).
- **Mensaje de commit** → se valida el formato Conventional Commits.

### CI/CD (cumplimiento inescapable)

Los hooks locales se saltan con `--no-verify`; el CI no. Copia la suite dentro del
repo y usa el workflow de `examples/ci/` (GitHub o GitLab), que ejecuta
`scripts/ci-check.sh` sobre los ficheros del PR (+ escaneo completo programable).

---

## Capa 2 — Memoria compartida (`AGENTS.md`)

Esta capa hace que rotar de agente/modelo funcione: el contexto vive en ficheros,
no en la ventana del modelo.

1. Copia `examples/orchestration/AGENTS.md` a la raíz de tu repo y rellénalo:
   contexto, reglas de oro, convenciones, cómo trabajar por bloques.
2. Crea `docs/spec/` (qué se construye y criterios de aceptación) y `docs/adr/`
   (decisiones). Es tu fuente de verdad.
3. `AGENTS.md` es un **estándar** que leen Cursor, Copilot, Codex, Cline y otros.
   Para los rezagados (Claude Code → `CLAUDE.md`, Gemini CLI → `GEMINI.md`), usa
   `examples/orchestration/link-agent-files.sh`, que los genera desde tu único
   `AGENTS.md`. No hay traducción de contenido: el agente inyecta el texto tal cual.

---

## Capa 3 — Agentes de IA

### 3a. El bundle de servicios (un clic)

`workspace-services/` empaqueta la infraestructura (gateway + conversor) en
contenedores. **No vive dentro de tus proyectos**: se levanta una vez y escucha en
`localhost`; cualquier proyecto se conecta por esa dirección.

```bash
cd workspace-services
cp .env.example .env          # pon SOLO las keys que uses (todas opcionales)
cp litellm/config.free.yaml litellm/config.yaml   # variante gratis (opcional)
./svc up                       # levanta gateway (:4000) + conversor (:8080)
```

CLI del bundle:

```bash
./svc convert doc.pdf > docs/spec/doc.md   # documento -> Markdown
./svc ask gemini "una pregunta"            # una consulta
./svc chat gemini                          # chat interactivo (necesita Python 3)
./svc down                                 # parar
```

### 3b. Modelos: gratis y de pago

Edita `workspace-services/litellm/config.yaml` con tus modelos. Opciones **gratis
sin tarjeta**: Groq (rápido), OpenRouter (variedad, DeepSeek/Qwen), Google AI
Studio (Gemini, contexto largo), Ollama (local, ilimitado, privado). Pon las keys
en `.env`. El bloque `fallbacks` rota al siguiente si uno falla o se agota.

Aviso importante: para **trabajo agéntico real** (Cline machaca la API), los tiers
gratis de nube topan con rate-limits enseguida. Para trabajar sin cortes: **Ollama
en local** (gratis, sin límites, ~16 GB RAM) o un proveedor **de pago barato**
(DeepSeek). Los tiers gratis valen para probar.

### 3c. Orquestador (Cline)

> Cline es el agente que hace los cambios en tu código (el chat solo devuelve
> texto). Alternativa: Kilo Code, si quieres el modo Orchestrator/Boomerang.

1. Instala la extensión **Cline** en VS Code.
2. **Abre la carpeta del proyecto** (así le indicas sobre qué trabajar).
3. Copia `AGENTS.md` y `.clinerules` a esa carpeta.
4. Ajustes de Cline (⚙️): **API Provider** = `OpenAI Compatible`, **Base URL** =
   `http://localhost:4000/v1`, **API Key** = tu `LITELLM_MASTER_KEY`
   (`sk-local-master`), **Model ID** = `gemini`/`strong`/`gpt`… (uno que soporte
   *tool use*).
5. Trabaja en modo **Act**, por bloques pequeños. Cline lee `AGENTS.md`, propone
   diffs sobre los ficheros y te pide confirmación; al commitear, **el gate valida
   su código igual que el tuyo**.

### 3d. Routing y orquestación avanzada (opcional)

- **Por dificultad**: RouteLLM (o los *tags*/presupuesto de LiteLLM) delante del
  gateway → lo caro a los potentes, lo simple a los baratos.
- **Por descomposición**: el modo Orchestrator de Cline/Kilo parte la tarea en
  subtareas y asigna un modelo por tipo. Requiere un modelo potente como planificador.

---

## Capa 4 — Conversión de documentos

Antes de adjuntar un PDF/DOCX a un agente, conviértelo a Markdown: gasta menos
tokens y reduce errores.

```bash
./svc convert especificacion.pdf > docs/spec/especificacion.md
```

Usa **MarkItDown** (rápido, formatos de oficina). Para documentos con tablas o
fórmulas complejas, cambia el motor a **Docling** (más pesado, más fiel).

---

## El día a día

1. Programas (tú o delegando en Cline por bloques, que lee `AGENTS.md`).
2. **Commit** → la suite formatea y analiza; si algo falla, lo arreglas.
3. **Push** → verificación en modo check + etapa pesada opcional.
4. **Pull request** → el CI repite las comprobaciones de forma inescapable.
5. Al tomar una decisión, la anotas en `docs/adr/` o `AGENTS.md` para que el
   siguiente agente/modelo la herede.

El gate garantiza la calidad; el contexto vive en ficheros; los modelos se relevan
solos (fallback) o por diseño. Ninguna pieza depende de la buena voluntad del modelo.

---

## Resolución de problemas (casos reales)

- **Windows: `execvpe(/bin/bash) failed`** al lanzar `bootstrap.bat` → tu PATH tiene
  el stub de WSL en System32. Los lanzadores actuales lo ignoran y priorizan Git
  Bash; si persiste, abre **Git Bash** y corre `./bootstrap.sh` directamente.
- **Windows: `Python was not found`** en `svc` → en Windows el ejecutable es
  `python`, no `python3`; el `svc` ya detecta el que exista. Si un alias fantasma
  de la Store interfiere, desactívalo en *Configuración → Apps → Alias de ejecución*.
- **`svc` "necesita un programa para abrir"** → en Windows ejecútalo con
  `bash svc ...` (no `./svc`).
- **LiteLLM lista modelos que no esperas / `private`** → cargó un `config.yaml`
  viejo. Sobrescríbelo y `./svc down && ./svc up`.
- **`401 No api key passed`** en `/v1/models` → añade la cabecera
  `-H "Authorization: Bearer sk-local-master"` (el `svc ask/chat` ya la manda).
- **`model not found` / 404** → el slug del modelo cambió (los catálogos gratis se
  mueven). Consulta el listado del proveedor y ajusta el `model:` en el config.
- **429 / rate-limit** con modelos gratis → es el límite del tier (tokens o
  requests por minuto/día). Cambia de modelo, o pásate a Ollama local / de pago.
- **Gemini `no longer available to new users`** → usa `gemini/gemini-flash-latest`
  (alias siempre vigente) o un flash concreto de tu lista
  (`curl ".../v1beta/models?key=TU_KEY"`).

---

## Estructura del proyecto

Ver el árbol completo en el **README.md**.