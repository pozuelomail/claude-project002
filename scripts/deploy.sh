#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Despliegue de WordPress ISO 27001 en Kubernetes via Helm
# Uso: ./deploy.sh <URL> [entorno] [namespace] [opciones]
#
# Ejemplos:
#   ./deploy.sh wp001.qforexwin.com
#   ./deploy.sh wp002.qforexwin.com pro mi-namespace
#   ./deploy.sh wp003.qforexwin.com dev wp-dev --dry-run
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Colores para output
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Argumentos
# -----------------------------------------------------------------------------
SITE_URL="${1:-}"
ENVIRONMENT="${2:-pro}"   # dev | pre | pro (por defecto pro para producción)
NAMESPACE="${3:-}"
EXTRA_ARGS="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../helm/wordpress-iso27001"
DEPLOY_DIR="${SCRIPT_DIR}/../deployments"

# -----------------------------------------------------------------------------
# Validaciones
# -----------------------------------------------------------------------------
usage() {
  echo ""
  echo "Uso: $0 <URL> [entorno] [namespace] [opciones-helm]"
  echo ""
  echo "  URL        FQDN del sitio (ej: wp001.qforexwin.com)"
  echo "  entorno    dev | pre | pro (defecto: pro)"
  echo "  namespace  Namespace Kubernetes (defecto: wp-<slug>)"
  echo "  opciones   Opciones extra para helm (ej: --dry-run)"
  echo ""
  echo "Ejemplos:"
  echo "  $0 wp001.qforexwin.com"
  echo "  $0 wp002.qforexwin.com dev wp-dev"
  echo "  $0 wp003.qforexwin.com pro wp-prod --dry-run"
  exit 1
}

if [[ -z "${SITE_URL}" ]]; then
  log_error "Falta el argumento URL."
  usage
fi

if [[ ! "${ENVIRONMENT}" =~ ^(dev|pre|pro)$ ]]; then
  log_error "Entorno no válido: '${ENVIRONMENT}'. Usa: dev, pre o pro."
  usage
fi

# Verificar dependencias
for cmd in helm kubectl; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Comando '${cmd}' no encontrado. Instálalo antes de continuar."
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# Derivar nombres desde la URL
# -----------------------------------------------------------------------------
# wp001.qforexwin.com -> slug: wp001-qforexwin-com
URL_SLUG=$(echo "${SITE_URL}" | tr '.' '-' | tr '[:upper:]' '[:lower:]')
RELEASE_NAME="wp-${URL_SLUG}"
NAMESPACE="${NAMESPACE:-wp-${URL_SLUG}}"

# Acortar si es demasiado largo (máx 53 chars para Helm)
RELEASE_NAME="${RELEASE_NAME:0:53}"

# -----------------------------------------------------------------------------
# Confirmación para producción — ISO 27001 A.12.1.2
# -----------------------------------------------------------------------------
if [[ "${ENVIRONMENT}" == "pro" && "${EXTRA_ARGS}" != *"--dry-run"* ]]; then
  echo ""
  log_warn "=========================================================="
  log_warn "  ATENCIÓN: Vas a desplegar en PRODUCCIÓN"
  log_warn "  URL:       https://${SITE_URL}"
  log_warn "  Release:   ${RELEASE_NAME}"
  log_warn "  Namespace: ${NAMESPACE}"
  log_warn "=========================================================="
  echo ""
  read -rp "¿Confirmas el despliegue en producción? (escribe 'si' para confirmar): " CONFIRM
  if [[ "${CONFIRM}" != "si" ]]; then
    log_info "Despliegue cancelado por el usuario."
    exit 0
  fi
fi

# -----------------------------------------------------------------------------
# Crear namespace si no existe
# -----------------------------------------------------------------------------
log_info "Verificando namespace '${NAMESPACE}'..."
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  log_info "Creando namespace '${NAMESPACE}'..."
  kubectl create namespace "${NAMESPACE}"
  # Etiquetas Pod Security Admission — ISO 27001 A.9.4
  kubectl label namespace "${NAMESPACE}" \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/audit=restricted \
    app.kubernetes.io/managed-by=helm \
    app.kubernetes.io/environment="${ENVIRONMENT}" \
    --overwrite
  log_ok "Namespace '${NAMESPACE}' creado."
else
  log_ok "Namespace '${NAMESPACE}' ya existe."
fi

# -----------------------------------------------------------------------------
# Construir comando Helm
# -----------------------------------------------------------------------------
VALUES_FILE="${CHART_DIR}/values-${ENVIRONMENT}.yaml"
if [[ ! -f "${VALUES_FILE}" ]]; then
  log_error "No existe el fichero de valores: ${VALUES_FILE}"
  exit 1
fi

# Directorio para guardar los valores generados
mkdir -p "${DEPLOY_DIR}"
OVERRIDE_FILE="${DEPLOY_DIR}/${RELEASE_NAME}-${ENVIRONMENT}.yaml"

# Generar fichero de override específico para esta URL/instancia
log_info "Generando fichero de override para '${SITE_URL}'..."
cat > "${OVERRIDE_FILE}" <<EOF
# Auto-generado por deploy.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Instancia: ${SITE_URL} | Entorno: ${ENVIRONMENT}
# NO editar manualmente — regenerar con deploy.sh

site:
  url: "${SITE_URL}"
  title: "WordPress ${SITE_URL}"
  adminEmail: "admin@${SITE_URL}"

global:
  environment: ${ENVIRONMENT}
EOF

log_ok "Override generado en: ${OVERRIDE_FILE}"

# -----------------------------------------------------------------------------
# Ejecutar Helm
# -----------------------------------------------------------------------------
log_info "Ejecutando helm upgrade --install..."
echo ""

# shellcheck disable=SC2086
helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${CHART_DIR}/values.yaml" \
  -f "${VALUES_FILE}" \
  -f "${OVERRIDE_FILE}" \
  --set "site.url=${SITE_URL}" \
  --set "global.environment=${ENVIRONMENT}" \
  --timeout 10m \
  --wait \
  --atomic \
  ${EXTRA_ARGS}

HELM_EXIT=$?

# -----------------------------------------------------------------------------
# Post-deploy: mostrar credenciales
# -----------------------------------------------------------------------------
if [[ ${HELM_EXIT} -eq 0 && "${EXTRA_ARGS}" != *"--dry-run"* ]]; then
  echo ""
  log_ok "=========================================================="
  log_ok "  Despliegue completado"
  log_ok "=========================================================="
  echo ""

  # Recuperar contraseña de admin desde Secret
  ADMIN_PASS=$(kubectl get secret "${RELEASE_NAME}-wordpress-iso27001-wordpress" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "No disponible")

  ADMIN_USER=$(kubectl get secret "${RELEASE_NAME}-wordpress-iso27001-wordpress" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "wpadmin")

  echo "  URL del sitio:    https://${SITE_URL}"
  echo "  Admin panel:      https://${SITE_URL}/wp-admin"
  echo "  Usuario admin:    ${ADMIN_USER}"
  echo "  Contraseña admin: ${ADMIN_PASS}"
  echo ""
  log_warn "GUARDA ESTAS CREDENCIALES DE FORMA SEGURA (ISO 27001 A.9.3)"
  echo ""

  # Guardar credenciales en fichero local (solo dev/pre)
  if [[ "${ENVIRONMENT}" != "pro" ]]; then
    CREDS_FILE="${DEPLOY_DIR}/${RELEASE_NAME}-credentials.txt"
    {
      echo "# Credenciales ${RELEASE_NAME} — ${ENVIRONMENT} — $(date)"
      echo "URL: https://${SITE_URL}"
      echo "Admin: https://${SITE_URL}/wp-admin"
      echo "Usuario: ${ADMIN_USER}"
      echo "Password: ${ADMIN_PASS}"
    } > "${CREDS_FILE}"
    chmod 600 "${CREDS_FILE}"
    log_info "Credenciales guardadas en: ${CREDS_FILE} (permisos 600)"
  fi
fi

exit ${HELM_EXIT}
