"""Compatibility package exposing the legacy ``config`` module path.

Historically the project shipped its Django settings under ``config.settings.*``.
The codebase now keeps the canonical implementations inside ``endo_api`` but we
still expose the old import locations so existing deployments and scripts keep
working without modification.
"""
