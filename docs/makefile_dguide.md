Ensure submodules: git submodule update --init --recursive
Install make if missing (Nix): nix-shell -p gnumake --run 'make help'
Build image: make build VERSION=1.0.0
Save tar: make save VERSION=1.0.0
Load into containerd (on RKE2 node): make load VERSION=1.0.0
Set secrets:
export DJANGO_SECRET_KEY=$(openssl rand -base64 32)
export DATABASE_URL=postgresql://user:pass@host:5432/db
Deploy: make deploy VERSION=1.0.0 HOST=endo-api.xulutions.net
Check: make status; make logs