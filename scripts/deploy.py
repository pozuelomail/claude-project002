#!/usr/bin/env python3
"""
deploy.py — Despliegue de WordPress ISO 27001 en Kubernetes via Helm
Uso: python deploy.py <URL> [--env {dev,pre,pro}] [--namespace NS] [--dry-run]

Ejemplos:
  python deploy.py wp001.qforexwin.com
  python deploy.py wp002.qforexwin.com --env dev
  python deploy.py wp003.qforexwin.com --env pro --namespace wp-prod
  python deploy.py wp004.qforexwin.com --dry-run
"""

import argparse
import base64
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Colores ANSI
# ---------------------------------------------------------------------------
class C:
    BLUE   = "\033[0;34m"
    GREEN  = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RED    = "\033[0;31m"
    NC     = "\033[0m"

def info(msg: str)  -> None: print(f"{C.BLUE}[INFO]{C.NC}  {msg}")
def ok(msg: str)    -> None: print(f"{C.GREEN}[OK]{C.NC}    {msg}")
def warn(msg: str)  -> None: print(f"{C.YELLOW}[WARN]{C.NC}  {msg}")
def error(msg: str) -> None: print(f"{C.RED}[ERROR]{C.NC} {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(cmd: list[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Ejecuta un comando y opcionalmente captura su salida."""
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
    )


def check_dependency(cmd: str) -> None:
    """Verifica que un binario esté disponible en el PATH."""
    result = subprocess.run(["which", cmd], capture_output=True)
    if result.returncode != 0:
        error(f"Comando '{cmd}' no encontrado. Instálalo antes de continuar.")
        sys.exit(1)


def url_to_slug(url: str) -> str:
    """
    Convierte una URL en un slug válido para Kubernetes.
    wp001.qforexwin.com -> wp001-qforexwin-com
    """
    slug = re.sub(r"[^a-zA-Z0-9]", "-", url).lower().strip("-")
    # Máx 53 chars para nombre de release Helm
    return slug[:53]


def namespace_exists(namespace: str) -> bool:
    result = subprocess.run(
        ["kubectl", "get", "namespace", namespace],
        capture_output=True
    )
    return result.returncode == 0


def create_namespace(namespace: str, environment: str) -> None:
    """Crea el namespace con etiquetas Pod Security Admission."""
    info(f"Creando namespace '{namespace}'...")
    run(["kubectl", "create", "namespace", namespace])
    # Etiquetas de seguridad — ISO 27001 A.9.4
    run([
        "kubectl", "label", "namespace", namespace,
        "pod-security.kubernetes.io/enforce=baseline",
        "pod-security.kubernetes.io/warn=restricted",
        "pod-security.kubernetes.io/audit=restricted",
        f"app.kubernetes.io/environment={environment}",
        "app.kubernetes.io/managed-by=helm",
        "--overwrite",
    ])
    ok(f"Namespace '{namespace}' creado con etiquetas de seguridad.")


def get_secret_value(secret_name: str, key: str, namespace: str) -> str:
    """Recupera un valor de un Secret de Kubernetes y lo decodifica."""
    try:
        result = run(
            ["kubectl", "get", "secret", secret_name,
             "-n", namespace,
             "-o", f"jsonpath={{.data.{key}}}"],
            capture_output=True,
        )
        return base64.b64decode(result.stdout).decode("utf-8")
    except Exception:
        return "No disponible"


def generate_override_file(
    url: str,
    environment: str,
    release_name: str,
    deploy_dir: Path,
) -> Path:
    """Genera el fichero YAML de override específico para esta instancia."""
    override_file = deploy_dir / f"{release_name}-{environment}.yaml"
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    content = f"""\
# Auto-generado por deploy.py — {timestamp}
# Instancia: {url} | Entorno: {environment}
# NO editar manualmente — regenerar con deploy.py

site:
  url: "{url}"
  title: "WordPress {url}"
  adminEmail: "admin@{url}"

global:
  environment: {environment}
"""
    override_file.write_text(content)
    override_file.chmod(0o640)
    ok(f"Override generado: {override_file}")
    return override_file


def confirm_production(url: str, release_name: str, namespace: str) -> bool:
    """Solicita confirmación explícita para despliegues en producción."""
    print()
    warn("=" * 58)
    warn("  ATENCIÓN: Vas a desplegar en PRODUCCIÓN")
    warn(f"  URL:       https://{url}")
    warn(f"  Release:   {release_name}")
    warn(f"  Namespace: {namespace}")
    warn("=" * 58)
    print()
    confirm = input("¿Confirmas el despliegue en producción? (escribe 'si' para confirmar): ")
    return confirm.strip().lower() == "si"


# ---------------------------------------------------------------------------
# Despliegue principal
# ---------------------------------------------------------------------------

def deploy(
    url: str,
    environment: str,
    namespace: str | None,
    dry_run: bool,
    extra_args: list[str],
) -> int:

    # Rutas
    script_dir  = Path(__file__).parent
    chart_dir   = script_dir / ".." / "helm" / "wordpress-iso27001"
    deploy_dir  = script_dir / ".." / "deployments"
    deploy_dir.mkdir(parents=True, exist_ok=True)

    # Nombres
    slug         = url_to_slug(url)
    release_name = f"wp-{slug}"
    namespace    = namespace or f"wp-{slug}"
    values_file  = chart_dir / f"values-{environment}.yaml"

    # Validaciones
    if not chart_dir.exists():
        error(f"No se encuentra el chart: {chart_dir.resolve()}")
        return 1

    if not values_file.exists():
        error(f"No existe el fichero de valores: {values_file}")
        return 1

    for dep in ("helm", "kubectl"):
        check_dependency(dep)

    # Confirmación pro
    if environment == "pro" and not dry_run:
        if not confirm_production(url, release_name, namespace):
            info("Despliegue cancelado por el usuario.")
            return 0

    # Namespace
    info(f"Verificando namespace '{namespace}'...")
    if not namespace_exists(namespace):
        create_namespace(namespace, environment)
    else:
        ok(f"Namespace '{namespace}' ya existe.")

    # Override file
    override_file = generate_override_file(url, environment, release_name, deploy_dir)

    # Construir comando Helm
    helm_cmd = [
        "helm", "upgrade", "--install", release_name,
        str(chart_dir.resolve()),
        "--namespace", namespace,
        "--create-namespace",
        "-f", str((chart_dir / "values.yaml").resolve()),
        "-f", str(values_file.resolve()),
        "-f", str(override_file.resolve()),
        "--set", f"site.url={url}",
        "--set", f"global.environment={environment}",
        "--timeout", "10m",
        "--wait",
        "--atomic",
    ]

    if dry_run:
        helm_cmd.append("--dry-run")

    helm_cmd.extend(extra_args)

    info("Ejecutando helm upgrade --install...")
    print()
    print(" ".join(helm_cmd))
    print()

    result = run(helm_cmd, check=False)

    if result.returncode != 0:
        error("El despliegue falló. Revisa los logs anteriores.")
        return result.returncode

    # Post-deploy: mostrar credenciales
    if not dry_run:
        print()
        ok("=" * 58)
        ok("  Despliegue completado")
        ok("=" * 58)
        print()

        secret_name = f"{release_name}-wordpress-iso27001-wordpress"
        admin_user  = get_secret_value(secret_name, "admin-user",     namespace)
        admin_pass  = get_secret_value(secret_name, "admin-password",  namespace)

        print(f"  URL del sitio:    https://{url}")
        print(f"  Admin panel:      https://{url}/wp-admin")
        print(f"  Usuario admin:    {admin_user}")
        print(f"  Contraseña admin: {admin_pass}")
        print()
        warn("GUARDA ESTAS CREDENCIALES DE FORMA SEGURA (ISO 27001 A.9.3)")
        print()

        # Guardar credenciales en fichero local (solo dev/pre)
        if environment != "pro":
            creds_file = deploy_dir / f"{release_name}-credentials.txt"
            creds_file.write_text(
                f"# Credenciales {release_name} — {environment} — {datetime.now()}\n"
                f"URL: https://{url}\n"
                f"Admin: https://{url}/wp-admin\n"
                f"Usuario: {admin_user}\n"
                f"Password: {admin_pass}\n"
            )
            creds_file.chmod(0o600)
            info(f"Credenciales guardadas en: {creds_file} (permisos 600)")

    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Despliega WordPress ISO 27001 en Kubernetes via Helm.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "url",
        help="FQDN del sitio (ej: wp001.qforexwin.com)"
    )
    parser.add_argument(
        "--env",
        choices=["dev", "pre", "pro"],
        default="pro",
        help="Entorno de despliegue (defecto: pro)"
    )
    parser.add_argument(
        "--namespace", "-n",
        default=None,
        help="Namespace Kubernetes (defecto: wp-<slug-url>)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Ejecutar helm con --dry-run (sin aplicar cambios)"
    )
    parser.add_argument(
        "extra",
        nargs="*",
        help="Argumentos extra para helm"
    )

    args = parser.parse_args()

    sys.exit(deploy(
        url=args.url,
        environment=args.env,
        namespace=args.namespace,
        dry_run=args.dry_run,
        extra_args=args.extra,
    ))


if __name__ == "__main__":
    main()
