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
