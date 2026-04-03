# Mapeo de Controles ISO 27001 — WordPress en Kubernetes

## Resumen de controles implementados

| Control ISO 27001 | Descripción | Implementación |
|-------------------|-------------|----------------|
| **A.9.2.3** | Gestión de privilegios de acceso | RBAC + ServiceAccount mínimo privilegio |
| **A.9.4** | Control de acceso a sistemas | PodSecurityContext, runAsNonRoot, NetworkPolicy |
| **A.10.1.1** | Política de controles criptográficos | TLS cert-manager, WordPress Security Keys aleatorias |
| **A.12.1.2** | Gestión de cambios | Confirmación obligatoria en pro, Helm atomic |
| **A.12.3.1** | Backup de información | Plugin UpdraftPlus instalado |
| **A.12.4.1** | Registro de eventos | Plugin WP Activity Log instalado |
| **A.12.6.1** | Gestión de vulnerabilidades técnicas | Plugin Wordfence, auto-updates core |
| **A.13.1.3** | Segregación de redes | NetworkPolicy ingress/egress estrictas |
| **A.14.2.5** | Principios de ingeniería de sistemas seguros | PHP hardening, cabeceras HTTP seguridad |
| **A.18.1.4** | Privacidad de información personal | Plugin Complianz GDPR |

## Plugins instalados y su justificación ISO 27001

### Wordfence Security
- **Control:** A.12.6.1, A.12.2.1
- **Función:** WAF (Web Application Firewall), escáner de malware, bloqueo de IPs maliciosas
- **Configuración recomendada:** Activar modo extendido de protección, alertas por email

### WP Activity Log
- **Control:** A.12.4.1 (Registro de eventos de operador y usuario)
- **Función:** Audit log completo de todas las acciones en WordPress
- **Configuración recomendada:** Retención mínima 90 días en pre/pro

### Really Simple SSL
- **Control:** A.10.1.1 (Criptografía), A.13.2.3
- **Función:** Forzar HTTPS en todo el sitio, gestionar cabeceras HSTS
- **Configuración recomendada:** Activar HSTS con preload en pro

### WP 2FA
- **Control:** A.9.4.2 (Procedimientos de inicio de sesión seguros)
- **Función:** Autenticación de dos factores para todos los usuarios admin
- **Configuración recomendada:** Obligatorio para roles Editor y Admin

### Limit Login Attempts Reloaded
- **Control:** A.9.4.3 (Sistema de gestión de contraseñas)
- **Función:** Bloqueo temporal tras intentos fallidos de login (fuerza bruta)
- **Configuración recomendada:** Bloquear tras 3 intentos, 24h lockout

### UpdraftPlus
- **Control:** A.12.3.1 (Backup de información)
- **Función:** Backup automático de ficheros y base de datos
- **Configuración recomendada:** Backup diario, retención 30 días, almacenamiento externo cifrado

### Complianz GDPR
- **Control:** A.18.1.4 (Privacidad y protección de datos personales)
- **Función:** Gestión de consentimiento de cookies, política de privacidad
- **Configuración recomendada:** Configurar según jurisdicción (GDPR para UE)

## Cabeceras HTTP de seguridad (configuradas en Ingress)

```
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Permissions-Policy: camera=(), microphone=(), geolocation=()
Content-Security-Policy: [restringida a self]
```

## Hardening PHP implementado (php-security.ini)

- `expose_php = Off` — Oculta versión de PHP
- `disable_functions` — Deshabilita funciones peligrosas (exec, shell_exec, etc.)
- Cookies de sesión con flags `httponly`, `secure`, `samesite=Strict`
- `display_errors = Off` — Sin información en respuestas HTTP

## Checklist de verificación post-despliegue

| Check | Estado | Responsable |
|-------|--------|-------------|
| TLS activo y certificado válido | ⏳ Pendiente | @AgenteSeguridad |
| Plugins ISO 27001 activados | ⏳ Pendiente | @AgenteDesarrollador |
| WP 2FA configurado para admin | ⏳ Pendiente | Admin WP |
| Backup inicial verificado | ⏳ Pendiente | @AgenteBackup |
| Wordfence escáner inicial ejecutado | ⏳ Pendiente | @AgenteSeguridad |
| Audit log WP Activity Log activo | ⏳ Pendiente | @AgenteSeguridad |
| NetworkPolicy verificada (no hay fugas) | ⏳ Pendiente | @AgenteSistemas |
| Credenciales admin en gestor de contraseñas | ⏳ Pendiente | Admin |
