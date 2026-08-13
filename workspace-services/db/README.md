# Base de datos de configuración (jerarquía de agentes y modelos)

Separa el **catálogo de modelos, las claves y la jerarquía de agentes/responsabilidades**
del código. Un cargador (`generate_config.py`) la lee y genera la config de LiteLLM
+ las definiciones de roles para el orquestador.

## Modelo de datos

- `providers` — proveedores (free/trial/paid/local) y su prefijo LiteLLM.
- `api_keys` — **referencia a variable de entorno** (no se guarda el secreto).
- `models` — modelos con `quality_tier` (1-5), coste, cuotas, `supports_tools`, prioridad.
- `agent_roles` — jerarquía nivel 0 (orquestador) → 3 (worker barato); cada rol con
  su `system_prompt` (su "AGENTS.md" / skill) y `min_quality_tier`.
- `task_types` — tipos de responsabilidad, con calidad requerida y presupuesto.
- `role_task_types` — qué rol atiende qué responsabilidad.

## Criterio de selección (lo que hace el cargador)

1. **Modelo con clave presente en el entorno** → se incluye.
2. **Modelo sin clave** → se salta.
3. **Modelo caído en runtime** → lo aparta el `cooldown` de LiteLLM.

La **escalera por rol**: entre los modelos que cumplen la calidad mínima del rol,
ordena **gratis primero** (coste asc) y luego mejor calidad primero. Así los buenos
modelos gratis se quedan en las capas altas y el de pago es el último recurso.

## Uso

```bash
# 1) Levanta los servicios (incluye Postgres):
./svc up

# 2) Inicializa la BD (esquema + datos de ejemplo):
./svc db-init

# 3) Edita tu catálogo/claves/roles con psql o tu cliente favorito.
#    Rellena en .env solo las claves que tengas (GEMINI_API_KEY, GROQ_API_KEY...).

# 4) Genera la config de LiteLLM desde la BD y reinicia el gateway:
./svc db-load
```

`db-load` escribe `litellm/config.generated.yaml`, lo copia a `config.yaml` y
reinicia LiteLLM. En Cline pon el Model ID en `auto`, o en un rol concreto
(`orchestrator`, `architect`, `backend`, `boilerplate`) para usar su escalera.

Requisitos del cargador (host): `pip install "psycopg[binary]" pyyaml`.

## Añadir modelos/proveedores/roles

Es solo `INSERT` en la tabla correspondiente y `./svc db-load`. No se toca código.
Ejemplo — añadir un proveedor y un modelo:

```sql
INSERT INTO providers (name, litellm_prefix, category) VALUES ('nueva','nueva/','free');
INSERT INTO api_keys (provider_id, env_var) VALUES
  ((SELECT id FROM providers WHERE name='nueva'), 'NUEVA_API_KEY');
INSERT INTO models (provider_id, slug, alias, quality_tier)
  VALUES ((SELECT id FROM providers WHERE name='nueva'), 'modelo-x', 'nueva-x', 3);
```

## Seguridad

Las claves **no** se guardan en la BD, solo el nombre de su variable de entorno;
el secreto vive en `.env`. Así un volcado de la BD no expone credenciales.
