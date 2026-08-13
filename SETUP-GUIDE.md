# Guía de instalación, configuración y uso

Sistema completo de desarrollo asistido por IA con control de calidad. Se compone
de **cuatro capas** que funcionan juntas; cada una aporta valor por sí sola.

---

## Herramientas usadas (resumen)

| Área | Herramientas |
|------|--------------|
| Formato/análisis Java | google-java-format, Checkstyle, PMD |
| Formato/análisis web | Prettier, ESLint (+typescript-eslint, plugin-html), Stylelint, html-validate |
| Markdown / XML / Docker | markdownlint-cli2, xmllint, hadolint |
| Perl | perltidy, perlimports, perl -cw, Perl::Critic |
| SQL (Oracle) | SQLFluff (dialecto Oracle) |
| Python | black, autopep8, isort, unify, eradicate, pylint, mypy |
| C / C++ | clang-format, cppcheck, clang-tidy |
| Shell | shfmt, shellcheck |
| Contenedor base | Docker, JDK 21 (Temurin), Node 20, Python 3, Perl |

---

## Capa 1 — Gate de calidad

### Qué se comprueba

Java, Markdown, XML, Dockerfile, HTML/XHTML, JS/TS, CSS/SCSS, JSP, **Perl**, **SQL (Oracle)**, **Python**, **C/C++** y **Shell**. Ver la tabla completa en el README.

### Configuración de reglas

- Perl: `config/.perlcriticrc`, `config/.perltidyrc`, `config/perlimports.toml`
- SQL (Oracle): `config/.sqlfluff`
- Python: `config/.pylintrc`
- C/C++: `config/.clang-format`, `config/.clang-tidy`

---

## Capa 2 — Hooks de Git locales

Los hooks de Git automatizan la ejecución de la suite de calidad en tu máquina local de forma transparente:

1. **`pre-commit`**:
   - Se ejecuta automáticamente al hacer `git commit`.
   - Identifica los archivos en staging, ejecuta la suite en modo `fix` dentro del contenedor Docker, aplica los formateadores y re-añade los archivos modificados al commit.
   - Si se detectan errores de sintaxis o violaciones de reglas que no se pueden corregir automáticamente, aborta el commit.

2. **`pre-push`**:
   - Se ejecuta automáticamente al hacer `git push`.
   - Ejecuta la suite en modo `check` (montaje de solo lectura) sobre todos los commits que se van a subir al servidor remoto.
   - Garantiza que ningún desarrollador pueda subir código mal formateado o con advertencias de calidad.

3. **`commit-msg`**:
   - Valida que el mensaje del commit cumpla estrictamente con la especificación de **Conventional Commits**.

4. **`prepare-commit-msg`**:
   - Genera una plantilla interactiva con el manifiesto de archivos modificados para facilitar la redacción del mensaje de commit.

---

## Capa 3 — Integración Continua (CI/CD)

La suite de calidad se puede integrar en cualquier plataforma de CI/CD (GitHub Actions, GitLab CI, Jenkins, etc.) utilizando el script `scripts/ci-check.sh`.

Este script optimiza el pipeline analizando únicamente los archivos modificados en el rango de commits del Pull Request o rama actual, evitando analizar todo el repositorio en cada ejecución y reduciendo drásticamente los tiempos de compilación.

---

## Capa 4 — Desarrollo Asistido por IA

Al utilizar agentes de IA o asistentes de código en tu IDE, la suite actúa como un "árbitro" de calidad implacable. Cualquier código generado por una IA debe pasar obligatoriamente por el gate de calidad local antes de ser aceptado en el repositorio, garantizando que el código generado mantenga siempre la consistencia de estilo, robustez y buenas prácticas del proyecto.
