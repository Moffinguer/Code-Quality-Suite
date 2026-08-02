# Code Quality Suite

Gate de calidad determinista para tus repos: en cada **commit** y **push**
formatea y analiza el código, y **bloquea** si no cumple. Da igual quién escriba
el código —tú o un agente de IA—, no entra si no pasa. Empaquetado en un
contenedor Docker, portable a Linux, Windows y macOS.

> Para montar además la capa de agentes de IA (modelos + orquestador + conversión
> de documentos) sobre esto, consulta **SETUP-GUIDE.md**.

---

## Qué comprueba y con qué herramientas

| Tipo de fichero | Formatea | Analiza |
|-----------------|----------|---------|
| **Java** | google-java-format | Checkstyle + PMD |
| **Markdown** | markdownlint-cli2 `--fix` | markdownlint-cli2 |
| **XML** | xmllint `--format` | xmllint (buena formación + XSD opcional) |
| **Dockerfile** | — | hadolint (+ ShellCheck en `RUN`) |
| **HTML / XHTML** | Prettier | html-validate + ESLint/Stylelint (embebidos) |
| **JS / JSX / TS / TSX** | Prettier | ESLint (+ typescript-eslint) |
| **CSS / SCSS** | Prettier | Stylelint |
| **JSP** | — | comprobación básica de delimitadores |

Extra clave: en un `.html`, el **JS/TS y CSS embebidos** dentro de `<script>` y
`<style>` también se formatean (Prettier) y se lintan (ESLint/Stylelint).

Versiones fijadas: google-java-format 1.28.0, Checkstyle 13.8.0, PMD 7.26.0,
hadolint 2.14.0, markdownlint-cli2 0.23.2, Prettier 3, ESLint 9, Stylelint 16,
html-validate 9; sobre JDK 21 (Temurin) y Node 20.

## Dos modos de ejecución

- **fix** (pre-commit): formatea in-place y analiza. Corrige lo corregible.
- **check** (pre-push, CI): verifica sin modificar nada; falla si algo no está
  formateado o incumple. Montaje de solo lectura.

---

## Requisitos

- **Docker** y **Git** en cada máquina (Linux, Windows con WSL2/Docker Desktop, o macOS).
- El repo objetivo **no** necesita Java, Node ni Maven: las herramientas viven
  dentro de la imagen.

## Instalación

Un solo comando: clona (o usa) el repo, detecta parámetros, prepara
`.gitattributes` e instala los hooks.

```bash
# Linux / macOS:
./bootstrap.sh https://github.com/spring-projects/spring-petclinic.git
./bootstrap.sh /ruta/a/tu/repo            # sobre un repo ya clonado

# Windows (cmd o doble clic):   bootstrap.bat <git-url|ruta> [destino]
# Windows (PowerShell):         .\bootstrap.ps1 <git-url|ruta> [destino]
# macOS (doble clic):           bootstrap.command
```

`bootstrap` hace automáticamente: clonar si le das una URL, **detectar la versión
de Java** del `pom.xml` (si no puede, la pregunta una vez y la guarda), crear o
actualizar el bloque gestionado de `.gitattributes`, construir la imagen (con tag
por `VERSION`) e instalar los cuatro hooks. Es **idempotente**: al reejecutarlo
respeta lo ya definido en `quality-suite.env`.

Los lanzadores de Windows buscan primero **Git Bash** y, si existe, usan el mismo
`bootstrap.sh` (una sola fuente de verdad); solo si no hay bash, `bootstrap.ps1`
usa una implementación nativa de PowerShell. macOS y Linux traen bash de serie.

**Ruta de clonado por defecto:** copia `bootstrap.config.example` a
`bootstrap.config` y define `CQS_WORKSPACE`.

**Instalación sin clonar/detectar:** `./install.sh /ruta/al/repo`.

---

## Uso

- **En cada commit** (`pre-commit`): formatea y analiza lo que está en staging;
  bloquea si hay violaciones. La primera vez construye la imagen si no existe.
- **En cada push** (`pre-push`): verifica en modo *check* todo el rango que
  empujas, y ejecuta la **etapa pesada** opcional si la configuraste.
- **Mensajes de commit**: `commit-msg` valida Conventional Commits;
  `prepare-commit-msg` precarga una plantilla con el manifiesto de ficheros.

### Los cuatro hooks instalados

| Hook | Función |
|------|---------|
| `pre-commit` | Formatea + analiza el staging (bloquea) |
| `pre-push` | Verifica el rango a empujar en modo check + etapa pesada opcional |
| `commit-msg` | Valida `<tipo>[(ámbito)][!]: <descripción ≤50>` (Conventional Commits) |
| `prepare-commit-msg` | Plantilla con tipos + manifiesto `A/M/D` de ficheros |

### Etapa pesada del pre-push (SpotBugs, cobertura, `tsc`…)

Lo que necesita compilar el proyecto entero no cabe en un pre-commit. Se activa
poniendo un comando en `quality-suite.env` (corre en el host con tu toolchain):

```bash
QUALITY_HEAVY_CMD="mvn -B verify"
```

### Ejecución manual

```bash
docker run --rm --network none -v "$PWD:/workspace" -w /workspace \
  code-quality-suite:latest  src/Foo.java  index.html  styles.scss  pom.xml
```

### CI/CD

En `examples/ci/` hay workflows listos (GitHub Actions y GitLab) que reconstruyen
la imagen y ejecutan `scripts/ci-check.sh` en modo check sobre los ficheros del
PR, con escaneo completo programable. Los hooks locales se saltan con
`--no-verify`; el CI no, así que es el gate **inescapable**.

---

## Configuración

Parámetros en `.git/hooks/quality-suite.env` del repo objetivo:

- `PMD_JAVA_VERSION` — nivel de lenguaje Java (se detecta del `pom.xml`).
- `COMMIT_TYPES`, `COMMIT_SUBJECT_MAX` — reglas del mensaje de commit.
- `QUALITY_HEAVY_CMD` — etapa pesada del pre-push.

Reglas de cada herramienta:

- Java: `config/checkstyle.xml`, `config/pmd-ruleset.xml`
- Markdown: `config/.markdownlint.jsonc`
- Dockerfile: `config/.hadolint.yaml`
- Web: `webtools/.prettierrc.json`, `webtools/eslint.config.mjs`,
  `webtools/.stylelintrc.json`, `webtools/.htmlvalidate.json`
- XML: variables `XML_FORMAT`, `XML_INDENT`, `XML_SCHEMA`

Tras cambiar configs, reconstruye: `./install.sh` (o sube `VERSION`).

---

## Seguridad

**Imagen:** base fijable por digest, usuario **no-root**, versiones pinneadas +
**verificación SHA-256** opcional (`scripts/update-checksums.sh`), descargas HTTPS.

**Ejecución (hooks):** `--network none`, `--read-only` + `--tmpfs /tmp`,
`--cap-drop ALL`, `--security-opt no-new-privileges`, UID del host en Linux, y
montaje de solo lectura en pre-push.

---

## Añadir un tipo de fichero nuevo

1. Crea `handlers/<tipo>.sh` respetando el contrato: respeta `QUALITY_MODE`,
   `exit 0` si limpio / `!=0` si hay violaciones.
2. Instala su herramienta en el `Dockerfile`.
3. Añade su rama en el clasificador de `entrypoint.sh` y su `run_handler`.

---

## Limitaciones conocidas

- **JSP** no tiene formateador/linter estándar fiable (los scriptlets rompen los
  parsers); solo se hace una comprobación básica de balance de delimitadores.
- **TypeScript**: se lintea, pero el *type-check* completo necesita tu
  `tsconfig.json` → encaja como etapa pesada (`tsc --noEmit`), no en pre-commit.
- **Staging parcial**: al re-añadir un fichero formateado se suben también sus
  cambios no-staged.
- **XML de contenido mixto**: el reformateo puede alterar espacios significativos
  (`XML_FORMAT=0` para solo validar).

---

## Estructura

```
code-quality-suite/
├── VERSION · Dockerfile · .dockerignore · .gitattributes
├── bootstrap.sh / .bat / .ps1 / .command   # instalación multiplataforma
├── bootstrap.config.example · install.sh
├── entrypoint.sh                            # despachador por tipo
├── handlers/  java · markdown · xml · dockerfile · web · jsp (.sh)
├── config/    checkstyle.xml · pmd-ruleset.xml · .markdownlint.jsonc · .hadolint.yaml
├── webtools/  package.json · .prettierrc.json · eslint.config.mjs · .stylelintrc.json · .htmlvalidate.json
├── hooks/     pre-commit · pre-push · commit-msg · prepare-commit-msg
├── scripts/   ci-check.sh · update-checksums.sh
├── examples/  ci/ (github, gitlab) · orchestration/ (AGENTS.md, cline, litellm)
├── workspace-services/   bundle de servicios de apoyo (ver SETUP-GUIDE.md)
├── README.md · SETUP-GUIDE.md
```