import os
import shutil
from pathlib import Path
from typing import Iterable, Set

from django.core.management.utils import get_random_secret_key


# --- Constants ---
DEFAULT_DB_PASSWORD = "changeme_in_production"  # Placeholder password


def _normalize_path(value: Path | str) -> Path:
    """Return an absolute path with user and quotes resolved."""

    if isinstance(value, Path):
        path = value
    else:
        cleaned = value.strip().strip("'\"")
        path = Path(cleaned)
    return path.expanduser().resolve()


def _resolve_env_path(env_name: str, default: Path) -> Path:
    raw = os.environ.get(env_name)
    if raw:
        return _normalize_path(raw)
    return _normalize_path(default)


def _collect_keys(lines: Iterable[str]) -> Set[str]:
    keys: Set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, _ = stripped.split("=", 1)
        keys.add(key.strip())
    return keys


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _ensure_quoted_value(lines: list[str], key: str) -> None:
    """Ensure the given key has a double-quoted value in the .env lines."""

    prefix = f"{key}="
    for index, raw_line in enumerate(lines):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not stripped.startswith(prefix):
            continue

        value = stripped[len(prefix) :].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            return

        unquoted = value.strip('"').strip("'")
        lines[index] = f'{key}="{unquoted}"'
        return


# --- Resolve key paths ---
conf_dir = _resolve_env_path("CONF_DIR", Path("./conf"))
conf_dir.mkdir(parents=True, exist_ok=True)
print(f"Configuration directory: {conf_dir}")

db_pwd_file = _resolve_env_path("DB_PWD_FILE", conf_dir / "db_pwd")
_ensure_parent(db_pwd_file)
if not db_pwd_file.exists():
    try:
        db_pwd_file.write_text(DEFAULT_DB_PASSWORD, encoding="utf-8")
        print(f"Created database password file at {db_pwd_file} (remember to change it in production).")
    except OSError as exc:
        print(f"ERROR: Unable to create database password file '{db_pwd_file}': {exc}")
else:
    print(f"Database password file already present at {db_pwd_file}.")

conf_template_dir = _resolve_env_path("CONF_TEMPLATE_DIR", Path("./conf_template"))

env_template_candidates = []
env_template_override = os.environ.get("ENV_TEMPLATE_FILE")
if env_template_override:
    env_template_candidates.append(_normalize_path(env_template_override))

env_template_candidates.append(_normalize_path(Path(".env.example")))
env_template_candidates.append(_normalize_path(conf_template_dir / "default.env"))

env_template_file = next((candidate for candidate in env_template_candidates if candidate.exists()), None)
if env_template_file is None:
    raise FileNotFoundError(
        "Unable to locate an environment template. Expected one of: ENV_TEMPLATE_FILE, .env.example, "
        f"or {conf_template_dir / 'default.env'}."
    )

print(f"Using environment template: {env_template_file}")


# --- Manage .env file ---
target_env = Path(".env")
if not target_env.exists():
    shutil.copy(env_template_file, target_env)
    print(f"Created .env file from template: {env_template_file}")
else:
    print(".env file already exists; merging missing keys from template.")

try:
    existing_lines = target_env.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise RuntimeError(f"Unable to read .env file at {target_env}: {exc}") from exc

existing_keys = _collect_keys(existing_lines)

try:
    template_lines = env_template_file.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise RuntimeError(f"Unable to read template file at {env_template_file}: {exc}") from exc

appended_from_template = 0
for raw_line in template_lines:
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue

    key, _ = stripped.split("=", 1)
    key = key.strip()
    if key in existing_keys:
        continue

    if existing_lines and existing_lines[-1].strip():
        existing_lines.append("")  # keep visual separation
    existing_lines.append(raw_line)
    existing_keys.add(key)
    appended_from_template += 1

if appended_from_template:
    print(f"Added {appended_from_template} missing entr{'y' if appended_from_template == 1 else 'ies'} from template.")


# --- Ensure secrets ---
if "DJANGO_SECRET_KEY" not in existing_keys:
    secret_key = get_random_secret_key()
    if existing_lines and existing_lines[-1].strip():
        existing_lines.append("")
    existing_lines.append(f'DJANGO_SECRET_KEY="{secret_key}"')
    existing_keys.add("DJANGO_SECRET_KEY")
    print("Generated DJANGO_SECRET_KEY and appended to .env.")

if "DJANGO_SALT" not in existing_keys:
    salt = get_random_secret_key()
    if existing_lines and existing_lines[-1].strip():
        existing_lines.append("")
    existing_lines.append(f'DJANGO_SALT="{salt}"')
    existing_keys.add("DJANGO_SALT")
    print("Generated DJANGO_SALT and appended to .env.")

_ensure_quoted_value(existing_lines, "DJANGO_SECRET_KEY")
_ensure_quoted_value(existing_lines, "DJANGO_SALT")


# --- Write updated .env ---
try:
    target_env.write_text("\n".join(existing_lines) + "\n", encoding="utf-8")
except OSError as exc:
    raise RuntimeError(f"Unable to write updated .env file at {target_env}: {exc}") from exc

print(f"Environment setup complete. Review {target_env} and {db_pwd_file} as needed.")
