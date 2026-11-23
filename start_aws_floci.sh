#!/usr/bin/env bash
# =============================================================================
# start_aws_floci.sh — Levanta el laboratorio AWS local (Floci)
#
#   - Red Docker propia `floci-net` (necesaria para que ECR funcione)
#   - Contenedor `floci`      → API de AWS en http://localhost:4566 (persistente)
#   - Contenedor `floci-aws-ui` → consola web en http://localhost:4500
#
# Es idempotente: se puede ejecutar las veces que quieras.
#   - Si algo no existe, lo crea.
#   - Si está parado, lo arranca.
#   - Si existe pero mal configurado (p. ej. creado con `floci start`), lo recrea.
# El estado de AWS vive en ~/floci-data (o en $FLOCI_DATA_DIR) y NO se borra al recrear.
#
# Uso:  ./start_aws_floci.sh
#       FLOCI_DATA_DIR=/otra/ruta ./start_aws_floci.sh
# Documentación: README.md y docs/INSTALACION-WSL.md
# =============================================================================
set -euo pipefail

NETWORK=floci-net
DATA_DIR="${FLOCI_DATA_DIR:-$HOME/floci-data}"
FLOCI_IMAGE=floci/floci:latest
UI_IMAGE=floci/floci-ui:0.7.0
HEALTH_TIMEOUT=90   # segundos

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
info() { printf '  \033[36m→\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$*"; exit 1; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

exists()  { docker container inspect "$1" >/dev/null 2>&1; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
on_net()  { docker container inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" | grep -w "$NETWORK" >/dev/null; }
has_env() { docker container inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | grep -x "$2" >/dev/null; }

# -----------------------------------------------------------------------------
step "1/5 Docker"
docker info >/dev/null 2>&1 || fail "Docker no responde. Abre Docker Desktop y vuelve a ejecutar."
ok "Docker disponible"

# -----------------------------------------------------------------------------
step "2/5 Red y carpeta de datos"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  ok "Red $NETWORK ya existe"
else
  docker network create "$NETWORK" >/dev/null && ok "Red $NETWORK creada"
fi
mkdir -p "$DATA_DIR" && ok "Datos persistentes en $DATA_DIR"

# -----------------------------------------------------------------------------
step "3/5 Floci (API de AWS :4566)"
run_floci() {
  docker run -d --name floci --network "$NETWORK" -p 4566:4566 \
    --restart unless-stopped \
    -v "$DATA_DIR":/app/data \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e FLOCI_STORAGE_MODE=persistent \
    -e FLOCI_STORAGE_PERSISTENT_PATH=/app/data \
    -e FLOCI_STORAGE_HOST_PERSISTENT_PATH="$DATA_DIR" \
    -e FLOCI_SERVICES_ECR_DOCKER_NETWORK="$NETWORK" \
    "$FLOCI_IMAGE" /app/application -Dquarkus.http.host=0.0.0.0 -Dfloci.security.allow-unsafe-network-exposure=true >/dev/null
}

if exists floci; then
  if on_net floci \
     && has_env floci "FLOCI_SERVICES_ECR_DOCKER_NETWORK=$NETWORK" \
     && has_env floci "FLOCI_STORAGE_MODE=persistent"; then
    if running floci; then ok "Floci ya estaba corriendo"
    else docker start floci >/dev/null && ok "Floci arrancado"; fi
  else
    warn "Floci existe pero con otra configuración (¿creado con 'floci start'?). Recreando…"
    docker rm -f floci >/dev/null
    run_floci && ok "Floci recreado (los datos de $DATA_DIR se conservan)"
  fi
else
  run_floci && ok "Floci creado"
fi

info "Esperando a que Floci esté healthy (máx. ${HEALTH_TIMEOUT}s)…"
for ((t=0; t<HEALTH_TIMEOUT; t+=3)); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' floci 2>/dev/null)" = "healthy" ] && break
  sleep 3
done
[ "$(docker inspect -f '{{.State.Health.Status}}' floci)" = "healthy" ] \
  || fail "Floci no llegó a healthy. Revisa: docker logs floci"
ok "Floci healthy"

# -----------------------------------------------------------------------------
step "4/5 Consola web (:4500)"
run_ui() {
  docker run -d --name floci-aws-ui --network "$NETWORK" -p 4500:4500 \
    --restart unless-stopped \
    -e AWS_DEFAULT_REGION=us-east-1 -e AWS_REGION=us-east-1 \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_SESSION_TOKEN=test \
    -e FLOCI_HOSTNAME=floci -e FLOCI_ENDPOINT=http://floci:4566 -e AWS_ENDPOINT_URL=http://floci:4566 \
    -e PORT=4500 -e FLOCI_CLOUD=aws -e FLOCI_INFO_URL=http://floci:4566/_floci/info \
    "$UI_IMAGE" ./server >/dev/null
}

if exists floci-aws-ui; then
  if on_net floci-aws-ui && has_env floci-aws-ui "FLOCI_ENDPOINT=http://floci:4566"; then
    if running floci-aws-ui; then ok "UI ya estaba corriendo"
    else docker start floci-aws-ui >/dev/null && ok "UI arrancada"; fi
  else
    warn "UI con otra configuración. Recreando…"
    docker rm -f floci-aws-ui >/dev/null
    run_ui && ok "UI recreada"
  fi
else
  run_ui && ok "UI creada"
fi

# Contenedores que Floci gestiona (registry ECR, clusters EKS) que hayan quedado parados
for c in $(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep -E '^floci-aws-(ecr-registry|eks-)' || true); do
  docker start "$c" >/dev/null && ok "Arrancado $c"
done

# -----------------------------------------------------------------------------
step "5/5 Verificación"
code() { curl -s -m 5 -o /dev/null -w '%{http_code}' "$1" || true; }

# grep -c (no -q): lee toda la salida, así pipefail no da un falso error
if [ "$(docker logs floci 2>&1 | grep -c 'Storage: *persistent' || true)" -ge 1 ]; then
  ok "Persistencia activa"
else
  warn "No veo 'Storage: persistent' en los logs"
fi

for ((t=0; t<30; t+=3)); do [ "$(code http://localhost:4566/v2/)" = 200 ] && break; sleep 3; done
[ "$(code http://localhost:4566/v2/)" = 200 ] && ok "ECR responde (200)" || warn "ECR no responde 200 todavía"

for ((t=0; t<15; t+=3)); do [ "$(code http://localhost:4500/)" = 200 ] && break; sleep 3; done
[ "$(code http://localhost:4500/)" = 200 ] && ok "UI responde (200)" || warn "UI no responde 200 todavía"

if command -v aws >/dev/null 2>&1; then
  if eval "$(floci env 2>/dev/null)" && ID=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
    ok "AWS CLI conectada: $ID"
  else
    warn "La AWS CLI no pudo conectar (¿falta 'eval \"\$(floci env)\"'?)"
  fi
fi

CLUSTERS=$(aws eks list-clusters --query clusters --output text 2>/dev/null || true)
REPOS=$(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text 2>/dev/null || true)
info "ECR repos: ${REPOS:-ninguno} · EKS clusters: ${CLUSTERS:-ninguno}"

cat <<'EOF'

  Laboratorio AWS listo 🚀
    API AWS : http://localhost:4566
    Consola : http://localhost:4500
    Datos   : ~/floci-data

  En tu terminal (si no lo hace ya tu ~/.bashrc):
    eval "$(floci env)"

  ⚠️  No uses 'floci start': recrea Floci sin la red de ECR.
      Si lo hiciste por error, vuelve a ejecutar este script.
EOF
