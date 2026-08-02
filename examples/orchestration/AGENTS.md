# AGENTS.md — directrices del proyecto para agentes de IA

> Estandar AGENTS.md: lo leen Cline, Kilo Code, Copilot y otros. Es la "memoria
> compartida": cualquier agente/modelo que retome el trabajo lee esto primero.

## Contexto del proyecto
- Qué es, para quién, y el objetivo actual (1-2 frases).
- Stack: Java <version>, Maven, <frameworks>.

## Reglas de oro (innegociables)
- Todo cambio pasa la suite de calidad (formato + Checkstyle + PMD + XML/MD/Docker).
- No se hace commit con `--no-verify`. La calidad no es negociable.
- Los tests de contrato los define una persona o un modo distinto al que implementa.
- Nunca inventes APIs: si dudas de una firma, búscala en el código.

## Convenciones
- Nomenclatura, estructura de paquetes, manejo de errores, logging: <resumir>.
- XML/Markdown se autoformatean; no pelees con el formateador.

## Cómo trabajar por bloques
- Divide cada tarea en subtareas pequeñas y verificables (una responsabilidad c/u).
- Al terminar un bloque: ejecuta la suite, resume lo hecho, y pasa el resumen.
- Modelo barato para tareas mecánicas; modelo potente para diseño/algoritmia.

## Dónde está la verdad
- Especificación/decisiones: `docs/spec/` y `docs/adr/`.
- Este fichero manda sobre cualquier suposición del agente.
