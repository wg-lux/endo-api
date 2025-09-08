How to test

Dev: manage dev && devenv up; override: DJANGO_PORT=8120 run-server
Docker dev: manage dev && manage build && manage copy && manage run
Docker prod: manage prod && manage build && manage copy && manage run (DB_CONFIG_FILE injected)
Verify logs and port bindings reflect env overrides.

