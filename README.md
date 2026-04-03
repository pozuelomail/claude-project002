# claude-project002 — WordPress ISO 27001 en Kubernetes

Plantilla Helm para desplegar WordPress en Kubernetes con hardening de seguridad
alineado a controles ISO 27001. Soporta múltiples instancias independientes
desplegadas a partir de un único script parametrizado por URL.

---

## Características

- **WordPress 6.4** con PHP 8.2 sobre Apache
- **MariaDB 10.11** como base de datos
- **TLS automático** vía cert-manager + Let's Encrypt
- **Plugins ISO 27001** instalados y activados automáticamente (WP-CLI)
- **Tres entornos** independientes: `dev`, `pre`, `pro`
- **NetworkPolicy** de segregación estricta (ingress/egress por componente)
- **Secretos auto-generados** (contraseñas y WordPress Security Keys aleatorias)
- **HPA** (Horizontal Pod Autoscaler) activo en producción
- **Cabeceras HTTP de seguridad** configuradas en Apache/.htaccess
- **PHP hardening** (`expose_php=Off`, funciones peligrosas deshabilitadas, cookies seguras)

---

## Estructura del proyecto

```
claude-project002/
├── helm/
│   └── wordpress-iso27001/
│       ├── Chart.yaml
│       ├── values.yaml              # Valores base comunes
│       ├── values-dev.yaml          # Overrides desarrollo
│       ├── values-pre.yaml          # Overrides preproducción
│       ├── values-pro.yaml          # Overrides producción
│       └── templates/
│           ├── _helpers.tpl
│           ├── namespace.yaml
│           ├── serviceaccount.yaml
│           ├── rbac.yaml
│           ├── secret-mariadb.yaml
│           ├── secret-wordpress.yaml
│           ├── configmap-wordpress.yaml
│           ├── configmap-nginx-headers.yaml
│           ├── pvc-mariadb.yaml
│           ├── pvc-wordpress.yaml
│           ├── deployment-mariadb.yaml
│           ├── deployment-wordpress.yaml
│           ├── service-mariadb.yaml
│           ├── service-wordpress.yaml
│           ├── ingress.yaml
│           ├── certificate.yaml
│           ├── networkpolicy.yaml
│           ├── job-plugins.yaml
│           └── hpa.yaml
├── scripts/
│   ├── deploy.sh                    # Despliegue via Bash
│   └── deploy.py                    # Despliegue via Python
├── deployments/                     # Overrides por instancia (auto-generados)
│   └── <release>-<env>.yaml
├── docs/
│   └── iso27001-controls.md         # Mapeo de controles ISO 27001
└── README.md
```

---

## Requisitos previos

| Componente | Versión mínima | Notas |
|-----------|---------------|-------|
| Kubernetes | 1.25+ | k3s, EKS, GKE, AKS, etc. |
| Helm | 3.10+ | |
| cert-manager | 1.12+ | Con `ClusterIssuer` letsencrypt-prod y letsencrypt-staging |
| ingress-nginx | 1.8+ | Con `externalIPs` o `LoadBalancer` apuntando a la IP pública |
| external-dns | Opcional | Para gestión automática de registros DNS |

### Configuración de ingress-nginx en VPS/bare-metal

En entornos sin cloud load balancer, añadir la IP pública como `externalIPs`:

```bash
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op":"add","path":"/spec/externalIPs","value":["<IP_PUBLICA>"]}]'
```

---

## Uso rápido

### Bash

```bash
# Producción (por defecto)
./scripts/deploy.sh wp001.qforexwin.com

# Con entorno explícito
./scripts/deploy.sh wp002.qforexwin.com pro
./scripts/deploy.sh wp003.qforexwin.com dev
./scripts/deploy.sh wp004.qforexwin.com pre

# Simulación sin aplicar cambios
./scripts/deploy.sh wp005.qforexwin.com pro "" --dry-run
```

### Python

```bash
# Producción
python scripts/deploy.py wp001.qforexwin.com

# Con opciones
python scripts/deploy.py wp002.qforexwin.com --env dev
python scripts/deploy.py wp003.qforexwin.com --env pro --namespace mi-namespace
python scripts/deploy.py wp004.qforexwin.com --dry-run
```

### Helm directo

```bash
helm upgrade --install <release> ./helm/wordpress-iso27001 \
  -f helm/wordpress-iso27001/values.yaml \
  -f helm/wordpress-iso27001/values-pro.yaml \
  --set site.url=midominio.com \
  --set global.environment=pro \
  --namespace wp-midominio \
  --create-namespace \
  --wait --atomic
```

---

## Plugins ISO 27001 instalados automáticamente

| Plugin | Versión | Control ISO 27001 | Función |
|--------|---------|------------------|---------|
| Wordfence Security | 8.x | A.12.6.1 / A.12.2.1 | WAF, escáner de malware, bloqueo IPs |
| WP Activity Log | 5.x | A.12.4.1 | Audit log completo de acciones |
| WP 2FA | 3.x | A.9.4.2 | Autenticación de dos factores |
| Limit Login Attempts Reloaded | 3.x | A.9.4.3 | Protección anti fuerza bruta |
| UpdraftPlus | 1.x | A.12.3.1 | Backup automático de ficheros y BD |
| Complianz GDPR | 7.x | A.18.1.4 | Consentimiento de cookies / GDPR |

> La instalación se realiza mediante un **Helm post-install hook** con WP-CLI.
> En upgrades posteriores, los plugins ya existentes no se reinstalan.

---

## Entornos

| Variable | dev | pre | pro |
|----------|-----|-----|-----|
| `site.url` | wp-dev.\* | wp-pre.\* | wp001.\* |
| `WP_DEBUG` | true | false | false |
| `FORCE_SSL_ADMIN` | false | true | true |
| `WP_AUTO_UPDATE_CORE` | false | false | minor |
| `cert-manager ClusterIssuer` | letsencrypt-staging | letsencrypt-staging | letsencrypt-prod |
| Réplicas WordPress | 1 | 1 | 2 (HPA 2-5) |
| PVC WordPress | 5 Gi | 10 Gi | 20 Gi |
| PVC MariaDB | 2 Gi | 5 Gi | 10 Gi |
| Rate limiting Ingress | No | No | 20 rps / 10 conn |

---

## Seguridad implementada (ISO 27001)

### Kubernetes
- **NetworkPolicy** separada por componente (`wordpress`, `mariadb`, `wpcli-job`)
- **RBAC** con Role vacío — ServiceAccount sin acceso a la API de Kubernetes
- **`automountServiceAccountToken: false`** en todos los pods
- **Pod Security Admission** con etiquetas `baseline/restricted` en el namespace
- **Secretos auto-generados** con `randAlphaNum 32/64` — nunca hardcodeados
- **PVC** independientes para datos WordPress y MariaDB

### WordPress / PHP
- `expose_php = Off` — oculta versión PHP en cabeceras
- `disable_functions` — bloquea `exec`, `shell_exec`, `system`, etc.
- Cookies de sesión con flags `httponly`, `secure`, `samesite=Strict`
- `display_errors = Off` en todos los entornos
- `DISALLOW_FILE_EDIT = true` — desactiva editor de ficheros en wp-admin
- `FORCE_SSL_ADMIN = true` en pre y pro
- WordPress Security Keys auto-generadas (64 chars cada una)

### Apache / .htaccess
- Listado de directorios deshabilitado (`Options -Indexes`)
- Bloqueo de acceso a `wp-config.php`, `.htaccess`, `xmlrpc.php`, `readme.html`
- Cabeceras de seguridad: `X-Frame-Options`, `X-XSS-Protection`, `X-Content-Type-Options`, `Referrer-Policy`
- Bloqueo de patrones de inyección XSS en query strings

---

## Recuperar credenciales de una instancia desplegada

```bash
NAMESPACE="wp-wp001-qforexwin-com"
RELEASE="wp-wp001-qforexwin-com"

kubectl get secret ${RELEASE}-wordpress-iso27001-wordpress \
  -n ${NAMESPACE} \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Instancias desplegadas

| Release | URL | Entorno | Namespace | Fecha |
|---------|-----|---------|-----------|-------|
| wp-wp001-qforexwin-com | https://wp001.qforexwin.com | pro | wp-wp001-qforexwin-com | 2026-04-03 |

---

## Notas conocidas

- El job WP-CLI (`job-plugins.yaml`) descarga WordPress core en tiempo de ejecución
  para instalar plugins. Requiere salida a internet en el pod desde el namespace.
- En single-node con `hostPort`, usar `NodePort` + `externalIPs` en el servicio
  `ingress-nginx-controller` para evitar conflicto con el ServiceLB (svclb) de k3s.
- Los warnings de PodSecurity `restricted` son informativos — el namespace tiene
  `enforce=baseline` que permite las capabilities necesarias para WordPress/Apache.
