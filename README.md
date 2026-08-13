# Code Quality Suite

Gate de calidad determinista para tus repos: en cada **commit** y **push**
formatea y analiza el código, y **bloquea** si no cumple. Da igual quién escriba
el código —tú o un agente de IA—, no entra si no pasa. Empaquetado en un
contenedor Docker, portable a Linux, Windows y macOS.

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
| **Perl** | perltidy + perlimports | perl -cw + Perl::Critic |
| **SQL (Oracle)** | sqlfluff format | sqlfluff lint (dialecto Oracle) |
| **Python** | black + autopep8 + isort | pylint + mypy |
| **C / C++** | clang-format | cppcheck + clang-tidy |
| **Shell** | shfmt | shellcheck |

## Dos modos de ejecución

- **fix** (pre-commit): formatea in-place y analiza. Corrige lo corregible.
- **check** (pre-push, CI): verifica sin modificar nada; falla si algo no está
  formateado o incumple. Montaje de solo lectura.

---

## Requisitos

- **Docker** y **Git** en cada máquina (Linux, Windows con WSL2/Docker Desktop, o macOS).
- El repo objetivo **no** necesita tener instalados los entornos o compiladores locales: todas las herramientas viven dentro de la imagen Docker.

---

## Estructura

```
code-quality-suite/
├── VERSION · Dockerfile · .dockerignore · .gitattributes
├── bootstrap.sh / .bat / .ps1 / .command   # instalación multiplataforma
├── bootstrap.config.example · install.sh
├── entrypoint.sh                            # despachador por tipo
├── handlers/  java · markdown · xml · dockerfile · web · jsp · perl · sql · python · c_cpp · shell (.sh)
├── config/    checkstyle.xml · pmd-ruleset.xml · .markdownlint.jsonc · .hadolint.yaml · .perlcriticrc · .perltidyrc · perlimports.toml · .sqlfluff · .pylintrc · .clang-format · .clang-tidy
├── webtools/  package.json · .prettierrc.json · eslint.config.mjs · .stylelintrc.json · .htmlvalidate.json
├── hooks/     pre-commit · pre-push · commit-msg · prepare-commit-msg
├── scripts/   ci-check.sh · update-checksums.sh
├── README.md · SETUP-GUIDE.md
```
