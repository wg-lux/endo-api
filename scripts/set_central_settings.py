from icecream import ic
import os
from pathlib import Path

# Use central settings if available, otherwise fall back to production
settings_module = os.environ.get("DJANGO_SETTINGS_MODULE_CENTRAL")
if not settings_module:
    settings_module = os.environ.get("DJANGO_SETTINGS_MODULE_PRODUCTION")
    if not settings_module:
        raise ValueError("Neither DJANGO_SETTINGS_MODULE_CENTRAL nor DJANGO_SETTINGS_MODULE_PRODUCTION environment variable is set")

env_path = Path(".env")

with open(env_path, "r", encoding="utf-8") as f:
    env_lines = f.readlines()

added = False
for i, line in enumerate(env_lines):
    if line.startswith("DJANGO_SETTINGS_MODULE"):
        env_lines[i] = f"DJANGO_SETTINGS_MODULE={settings_module}\n"
        added = True
        break

if not added:
    env_lines.append(f"DJANGO_SETTINGS_MODULE={settings_module}\n")

with open(env_path, "w", encoding="utf-8") as f:
    f.writelines(env_lines)

ic(f"DJANGO_SETTINGS_MODULE set to {settings_module}")
