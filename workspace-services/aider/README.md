# Aider — orquestador por CLI (alternativa a Cline)

Aider edita el código directamente en tu repo git, **commitea cada cambio**, usa
muchas menos llamadas que Cline (repo map comprimido + solo los ficheros que
añades) y no depende de VSCode.

## Cómo encaja con tu sistema

Aider tiene **tres papeles de modelo**, y los mapeamos a los **alias de rol que
genera tu BD** (cada uno con su escalera y su cooldown en LiteLLM):

| Papel de Aider | Alias de rol (BD) | Qué hace |
|----------------|-------------------|----------|
| `--model` (architect) | `openai/architect` | Planifica el cambio (escalera fuerte) |
| `--editor-model` | `openai/backend` | Aplica los diffs (escalera media) |
| `--weak-model` | `openai/boilerplate` | Mensajes de commit, resúmenes (escalera barata + local) |

El modo architect divide en dos pasos (plan + edición) y cuesta un 30-50% menos
que usar el modelo fuerte para todo, además de reducir errores en refactors
multi-fichero.

## Uso

```bash
# Requisito (host):  pip install aider-chat
# Con los servicios levantados (svc up) y la BD cargada (db-init + db-load):
./svc aider /ruta/a/petclinic
```

El lanzador apunta Aider a `http://localhost:4000/v1` con tu `LITELLM_MASTER_KEY`,
carga `AGENTS.md` como directrices de solo lectura, y activa cache de prompts. Ya
dentro, le pides cambios en lenguaje natural y él edita+commitea.

Si prefieres no usar el lanzador, copia `aider.conf.yml` como `.aider.conf.yml`
en tu repo y exporta `OPENAI_API_KEY`.

## Límite honesto: Aider NO es el orquestador jerárquico completo

Aider usa 3 de tus roles (architect/backend/boilerplate) para **un cambio**. No
descompone una tarea grande y la reparte entre `backend`, `frontend` y
`boilerplate` como workers independientes — eso es una capa por encima.

Para esa descomposición por dominio hay dos caminos, para más adelante:

1. **Manual/por sesión:** lanzas Aider con el rol adecuado según la tarea
   (`--model openai/frontend` para UI, `openai/boilerplate` para tests…). Simple
   y ya funciona con lo que tienes.
2. **Orquestador fino:** un script que lea `roles.generated.json` + `task_types`,
   parta la petición en subtareas y llame a Aider (o al gateway) con el alias de
   rol de cada una. Es la pieza que convierte esto en el árbol completo.

La resiliencia (apartar modelos agotados) ya está debajo, en LiteLLM: Aider ni se
entera de qué modelo real le sirve cada llamada.
