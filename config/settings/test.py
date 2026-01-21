"""Test settings alias. Uses ``endo_api.settings_test`` when available.

If the dedicated test module is missing we fall back to the development
configuration so existing test pipelines keep a usable baseline.
"""

try:  # pragma: no cover - import side effect only
    from endo_api.settings_test import *  # type: ignore # noqa: F401,F403
except ModuleNotFoundError:  # pragma: no cover
    from endo_api.settings_dev import *  # type: ignore # noqa: F401,F403
