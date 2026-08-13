# Code Quality Suite

Gate de calidad determinista para tus repositorios: en cada **commit** y **push**
formatea y analiza el código, y **bloquea** la operación si no cumple con los estándares.
Da igual quién escriba el código —tú, tu equipo o un agente de IA—, no entra al repositorio si no pasa las validaciones.
Empaquetado en un contenedor Docker, portable a Linux, Windows (WSL2) y macOS.

---

## Qué comprueba y con qué herramientas

| Tipo de fichero | Formatea | Analiza |
|-----------------|----------|---------|
| **Java** | google-java-format | Checkstyle + PMD |
| **Markdown** | markdownlint-cli2 `--fix` | markdownlint-cli2 |
| **XML** | xmllint `--format` | xmllint (buena formación + XSD opcional) |
| **Dockerfile** | — | hadolint (+ ShellCheck en bloques `RUN`) |
| **HTML / XHTML** | Prettier | html-validate + ESLint/Stylelint (embebidos) |
| **JS / JSX / TS / TSX** | Prettier | ESLint (+ typescript-eslint) |
| **CSS / SCSS** | Prettier | Stylelint |
| **JSP** | — | comprobación básica de delimitadores |
| **Perl** | perltidy + perlimports | perl -cw + Perl::Critic |
| **SQL (Oracle)** | sqlfluff format | sqlfluff lint (dialecto Oracle) |
| **Python** | black + autopep8 + isort | pylint + mypy |
| **C / C++** | clang-format | cppcheck + clang-tidy |
| **Shell** | shfmt | shellcheck |

---

## Dos modos de ejecución

La suite opera bajo dos filosofías distintas según el momento del ciclo de vida del desarrollo:

1. **Modo `fix` (pre-commit)**:
   - **Objetivo**: Ayudar al desarrollador aplicando correcciones automáticas.
   - **Comportamiento**: Formatea los archivos modificados *in-place* (reescribiendo el archivo en tu espacio de trabajo) y luego ejecuta los analizadores estáticos. Corrige automáticamente todo lo que sea corregible (estilo, imports, espaciado).
   - **Uso**: Se ejecuta automáticamente al hacer `git commit`.

2. **Modo `check` (pre-push, CI/CD)**:
   - **Objetivo**: Garantizar la inmutabilidad y verificar el cumplimiento estricto.
   - **Comportamiento**: Realiza un montaje de solo lectura (`ro`) del repositorio. Verifica que todo el código esté perfectamente formateado y libre de violaciones sin modificar un solo byte. Si detecta código mal formateado o con advertencias, la ejecución falla y bloquea el push o la compilación.
   - **Uso**: Se ejecuta automáticamente al hacer `git push` o en pipelines de CI/CD.

---

## Requisitos

- **Docker** instalado y en ejecución.
- **Git** configurado en la máquina local (Linux, Windows con WSL2/Docker Desktop, o macOS).
- El repositorio objetivo **no** necesita tener instalados los entornos de ejecución, compiladores o linters locales: todas las herramientas y runtimes viven de forma aislada dentro de la imagen Docker.

---

## Estructura del Proyecto

```
code-quality-suite/
├── VERSION                                  # Versión actual de la suite
├── Dockerfile                               # Definición de la imagen base con todas las herramientas
├── .dockerignore                            # Exclusiones para optimizar el build de Docker
├── .gitattributes                           # Normalización de saltos de línea (LF) para scripts
├── bootstrap.sh / .bat / .ps1 / .command    # Scripts de instalación multiplataforma
├── bootstrap.config.example                 # Configuración de ejemplo para el bootstrap
├── install.sh                               # Script de instalación de hooks en repositorios locales
├── entrypoint.sh                            # Despachador agnóstico que agrupa archivos por tipo/shebang
│
├── handlers/                                # Scripts específicos de análisis por lenguaje
│   ├── java.sh
│   ├── markdown.sh
│   ├── xml.sh
│   ├── dockerfile.sh
│   ├── web.sh
│   ├── jsp.sh
│   ├── perl.sh                              # Formateo con perltidy/perlimports y análisis con perlcritic
│   ├── sql.sh                               # Formateo y análisis de SQL Oracle con sqlfluff
│   ├── python.sh                            # Formateo con black/isort y análisis con pylint/mypy
│   ├── c_cpp.sh                             # Formateo con clang-format y análisis con cppcheck/clang-tidy
│   └── shell.sh                             # Formateo con shfmt y análisis con shellcheck
│
├── config/                                  # Archivos de configuración de las herramientas de análisis
│   ├── checkstyle.xml
│   ├── pmd-ruleset.xml
│   ├── .markdownlint.jsonc
│   ├── .hadolint.yaml
│   ├── .perlcriticrc                        # Reglas de Perl::Critic
│   ├── .perltidyrc                          # Reglas de formateo de Perl::Tidy
│   ├── perlimports.toml                     # Configuración de ordenación de imports de Perl
│   ├── .sqlfluff                            # Configuración de SQLFluff (dialecto Oracle)
│   ├── .pylintrc                            # Reglas de Pylint para Python
│   ├── .clang-format                        # Estilo de formateo C/C++
│   └── .clang-tidy                          # Reglas de análisis estático C/C++
│
├── webtools/                                # Entorno Node.js aislado para herramientas web
│   ├── package.json
│   ├── .prettierrc.json
│   ├── eslint.config.mjs
│   ├── .stylelintrc.json
│   └── .htmlvalidate.json
│
├── hooks/                                   # Hooks de Git listos para ser instalados
│   ├── pre-commit                           # Formatea y analiza archivos en staging
│   ├── pre-push                             # Verifica cambios antes de subirlos al remoto
│   ├── commit-msg                           # Valida mensajes bajo Conventional Commits
│   └── prepare-commit-msg                   # Genera plantilla de mensaje con manifiesto de cambios
│
└── scripts/                                 # Utilidades de mantenimiento y CI/CD
    ├── ci-check.sh                          # Script optimizado para ejecutar en pipelines de CI
    └── update-checksums.sh                  # Utilidad para actualizar y fijar hashes de herramientas
```

---

## Instalación y Uso Rápido

Para instalar la suite de calidad en cualquier repositorio local, ejecuta el script de bootstrap proporcionando la ruta de tu repositorio:

```bash
./bootstrap.sh /ruta/a/tu/repositorio
```

Esto realizará las siguientes acciones de forma automática:
1. Construirá la imagen Docker localmente si no existe.
2. Copiará los hooks de Git (`pre-commit`, `pre-push`, `commit-msg`, `prepare-commit-msg`) a la carpeta `.git/hooks/` de tu repositorio.
3. Creará un archivo de configuración local `quality-suite.env` dentro de la carpeta de hooks para personalizar variables de entorno.
4. Configurará `.gitattributes` para asegurar que los scripts mantengan saltos de línea LF.

---

## Integración Continua (CI/CD)

El script `scripts/ci-check.sh` está diseñado para integrarse fácilmente en cualquier pipeline de CI/CD (como GitHub Actions o GitLab CI). Ejecuta la suite en modo `check` únicamente sobre los archivos modificados en el Pull Request o commit actual, optimizando los tiempos de ejecución.

### Ejemplo para GitHub Actions:

```yaml
name: Quality Gate
on: [pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Run Quality Suite
        run: |
          docker build -t code-quality-suite:latest .
          ./scripts/ci-check.sh origin/main
```
