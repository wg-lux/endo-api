import shutil
from pathlib import Path
from endoreg_db.utils import DbConfig
import os

from regex import TEMPLATE

# fetch environment variables
TEMPLATE_DIR = os.environ.get("CONF_TEMPLATE_DIR", "./conf_template")
assert TEMPLATE_DIR, "Missing CONF_TEMPLATE_DIR environment variable"
TEMPLATE_DIR = Path(TEMPLATE_DIR).resolve()
TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)

CONF_DIR = Path(os.environ.get("CONF_DIR", "./conf")).resolve()
assert CONF_DIR, "Missing CONF_DIR environment variable"
CONF_DIR.mkdir(parents=True, exist_ok=True)

DB_PWD_PATH = Path(os.environ.get("DB_PWD_FILE", "./conf/db_pwd")).resolve()
assert DB_PWD_PATH, "Missing DB_PWD_FILE environment variable"

DB_CFG_PATH = TEMPLATE_DIR / "db.yaml"

CONF_TARGETS = {
    "root": CONF_DIR,
    "db": CONF_DIR / "db.yaml",
}


def main(conf_dir: Path = CONF_TARGETS["root"], template_dir: Path = TEMPLATE_DIR):
    """
    Generate the database configuration file from a template if it does not already exist.
    
    If the configuration directory does not exist, it is created. If the database configuration file is missing, it is generated from the template, validated, and written to the target location with an option to prompt for override.
    """
    db_template = template_dir / "db.yaml"
    assert db_template.exists(), f"Missing Template {DB_CFG_PATH}"

    if not conf_dir.exists():
        conf_dir.mkdir()

    if not CONF_TARGETS["db"].exists():
        db_cfg = DbConfig.from_file(DB_CFG_PATH)
        db_cfg.custom_validate()
        db_cfg.to_file(CONF_TARGETS["db"].as_posix(), ask_override=True)


if __name__ == "__main__":
    main()
