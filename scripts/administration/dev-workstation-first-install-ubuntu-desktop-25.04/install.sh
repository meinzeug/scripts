cat >/tmp/setup_devpc.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ===== Eingaben =====
read -rp "Hostname [devpc-dennis]: " HOSTNAME_NEW; HOSTNAME_NEW=${HOSTNAME_NEW:-devpc-dennis}
read -rp "Git Benutzername (Voller Name) [Dennis von W.]: " GIT_NAME; GIT_NAME=${GIT_NAME:-Dennis von W.}
read -rp "Git E-Mail [error2k84@googlemail.com]: " GIT_EMAIL; GIT_EMAIL=${GIT_EMAIL:-error2k84@googlemail.com}
read -rp "GitHub Username [meinzeug]: " GH_USER; GH_USER=${GH_USER:-meinzeug}
read -rp "Projektverzeichnis [${HOME}/Projekte/${GH_USER}]: " PROJ_DIR; PROJ_DIR=${PROJ_DIR:-${HOME}/Projekte/${GH_USER}}
echo "==> Host=${HOSTNAME_NEW} Git=${GIT_NAME}<${GIT_EMAIL}> GH=${GH_USER} Projekte=${PROJ_DIR}"

# ===== Hostname =====
sudo hostnamectl set-hostname "${HOSTNAME_NEW}"
grep -q "${HOSTNAME_NEW}" /etc/hosts || echo "127.0.1.1 ${HOSTNAME_NEW}" | sudo tee -a /etc/hosts >/dev/null

# ===== Updates + Tools =====
sudo apt update
sudo apt -y upgrade
sudo apt -y dist-upgrade
sudo apt -y install git make curl wget unzip zip jq ripgrep fzf bat tmux htop build-essential ca-certificates gnupg lsb-release ufw zsh iproute2
sudo apt -y autoremove && sudo apt -y autoclean

# ===== Docker =====
sudo apt -y remove docker docker-engine docker.io containerd runc || true
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $UBUNTU_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"

# ===== Firewall =====
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
yes | sudo ufw enable

# ===== Git + GitHub =====
command -v gh >/dev/null 2>&1 || sudo apt -y install gh
git config --global user.name "${GIT_NAME}"
git config --global user.email "${GIT_EMAIL}"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "code --wait"
git config --global credential.helper store

# SSH-Key
[ -f "${HOME}/.ssh/id_ed25519" ] || { mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"; ssh-keygen -t ed25519 -C "${GIT_EMAIL}" -f "${HOME}/.ssh/id_ed25519" -N ""; }
# gh auth + Key hochladen
gh auth status >/dev/null 2>&1 || gh auth login -w -s "repo,workflow,read:org"
PUBKEY=$(cat "${HOME}/.ssh/id_ed25519.pub")
gh ssh-key list --json title,key | jq -e --arg k "$PUBKEY" '[.[]|.key]|index($k) != null' >/dev/null || gh ssh-key add "${HOME}/.ssh/id_ed25519.pub" -t "${HOSTNAME_NEW}"

# ===== VS Code =====
snap list | grep -q "^code " || sudo snap install code --classic
EXTS=( ms-azuretools.vscode-docker ms-vscode-remote.remote-containers github.vscode-pull-request-github
       ms-python.python ms-python.vscode-pylance ms-vscode.cpptools ms-vscode.vscode-typescript-next
       dbaeumer.vscode-eslint esbenp.prettier-vscode redhat.vscode-yaml hashicorp.terraform
       tamasfe.even-better-toml ms-vscode.makefile-tools eamodio.gitlens oderwat.indent-rainbow
       ms-vscode.remote-repositories )
for e in "${EXTS[@]}"; do code --install-extension "$e" >/dev/null || true; done

CODE_USER_DIR="${HOME}/.config/Code/User"
mkdir -p "${CODE_USER_DIR}"
[ -f "${CODE_USER_DIR}/settings.json" ] && cp "${CODE_USER_DIR}/settings.json" "${CODE_USER_DIR}/settings.json.bak.$(date +%Y%m%d%H%M%S)"
cat > "${CODE_USER_DIR}/settings.json" <<'JSON'
{
  "editor.formatOnSave": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "git.autofetch": true,
  "terminal.integrated.defaultProfile.linux": "zsh",
  "editor.rulers": [100],
  "docker.dockerPath": "/usr/bin/docker",
  "docker.host": "unix:///var/run/docker.sock",
  "remote.containers.dockerPath": "/usr/bin/docker",
  "remote.containers.defaultExtensions": [
    "ms-azuretools.vscode-docker","eamodio.gitlens","dbaeumer.vscode-eslint","esbenp.prettier-vscode","redhat.vscode-yaml"
  ],
  "python.defaultInterpreterPath": "python3",
  "yaml.validate": true,
  "eslint.format.enable": true,
  "prettier.singleQuote": true,
  "prettier.printWidth": 100,
  "redhat.telemetry.enabled": false,
  "telemetry.telemetryLevel": "off",
  "workbench.colorTheme": "Default Dark Modern"
}
JSON

# ===== Port-Mapper =====
sudo install -d -m 0755 /usr/local/bin
sudo tee /usr/local/bin/portmap >/dev/null <<'PM'
#!/usr/bin/env bash
set -euo pipefail
DB="${HOME}/.config/portmap/ports.json"
mkdir -p "$(dirname "$DB")"
[ -f "$DB" ] || echo '{"reservations":{}}' > "$DB"
jqget() { jq -r "$1" "$DB"; }
jqset() { TMP="$(mktemp)"; jq "$1" "$DB" > "$TMP" && mv "$TMP" "$DB"; }
range_for() {
  case "${1:-other}" in
    github) echo "${PORTMAP_GH_START:-10000} ${PORTMAP_GH_END:-20000}" ;;
    other)  echo "${PORTMAP_APP_START:-25000} ${PORTMAP_APP_END:-28000}" ;;
    *)      echo "${PORTMAP_APP_START:-25000} ${PORTMAP_APP_END:-28000}" ;;
  esac
}
in_use() { ss -ltn "( sport = :$1 )" | tail -n +2 | grep -q .; }
next_free() {
  local start=$1 end=$2
  for ((p=start; p<=end; p++)); do
    in_use "$p" && continue
    jq -e --argjson port "$p" '.reservations|to_entries|map(.value.port)|index($port)!=null' "$DB" >/dev/null && continue
    echo "$p"; return 0
  done
  return 1
}
case "${1:-help}" in
  reserve)
    typ=${2:-other}; name=${3:-}; pref=${4:-}
    [ -n "$name" ] || { echo "name missing" >&2; exit 1; }
    if jq -e --arg n "$name" '.reservations[$n]' "$DB" >/dev/null; then jq -r --arg n "$name" '.reservations[$n].port' "$DB"; exit 0; fi
    read s e < <(range_for "$typ")
    port=""
    if [ -n "${pref:-}" ] && [ "$pref" -ge "$s" ] && [ "$pref" -le "$e" ] && ! in_use "$pref" && ! jq -e --argjson port "$pref" '.reservations|to_entries|map(.value.port)|index($port)!=null' "$DB" >/dev/null; then port="$pref"; fi
    if [ -z "${port:-}" ]; then port="$(next_free "$s" "$e")"; fi
    [ -n "$port" ] || { echo "no free port in range $s-$e" >&2; exit 2; }
    jqset --arg n "$name" --arg t "$typ" --argjson p "$port" '.reservations[$n] = {type:$t, port:$p}'
    echo "$port"
    ;;
  release)
    name=${2:-}; [ -n "$name" ] || { echo "name missing" >&2; exit 1; }
    jqset --arg n "$name" 'del(.reservations[$n])'
    ;;
  show)
    jq '.reservations' "$DB"
    ;;
  *)
    echo "usage: portmap reserve <github|other> <name> [preferred] | release <name> | show"
    ;;
esac
PM
sudo chmod +x /usr/local/bin/portmap
sudo tee /etc/profile.d/portmap.sh >/dev/null <<'PR'
export PORTMAP_GH_START=10000
export PORTMAP_GH_END=20000
export PORTMAP_APP_START=25000
export PORTMAP_APP_END=28000
PR

# ===== Portainer (Ports aus „other“-Range) =====
EDGE_PORT="$(PORTMAP_APP_START=25000 PORTMAP_APP_END=28000 portmap reserve other portainer-edge 25800 || true)"; [ -n "${EDGE_PORT:-}" ] || EDGE_PORT=25800
UI_PORT="$(PORTMAP_APP_START=25000 PORTMAP_APP_END=28000 portmap reserve other portainer-ui 25443 || true)";     [ -n "${UI_PORT:-}" ] || UI_PORT=25443
sudo docker volume create portainer_data >/dev/null
if sudo docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then sudo docker rm -f portainer >/dev/null || true; fi
sudo docker run -d -p "${EDGE_PORT}:8000" -p "${UI_PORT}:9443" --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest

# ===== Templates für Dev-Container =====
TPL="${HOME}/.devcontainer-templates"
mkdir -p "${TPL}"
cat > "${TPL}/Dockerfile" <<'DCK'
FROM debian:stable-slim
RUN apt-get update && apt-get install -y git curl ca-certificates build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /work
CMD ["sleep","infinity"]
DCK
cat > "${TPL}/docker-compose.yml" <<'YML'
services:
  app:
    build: .
    command: sleep infinity
    volumes: [ ".:/work" ]
    environment: [ "APP_PORT=${APP_PORT:-3000}" ]
    ports: [ "${PORT:-0}:${APP_PORT:-3000}" ]
YML
cat > "${TPL}/devcontainer.json" <<'JSON'
{
  "name": "dev",
  "build": { "dockerfile": "../Dockerfile" },
  "workspaceFolder": "/work",
  "mounts": ["source=${localWorkspaceFolder},target=/work,type=bind"],
  "customizations": { "vscode": { "extensions": [
    "ms-azuretools.vscode-docker","eamodio.gitlens","dbaeumer.vscode-eslint","esbenp.prettier-vscode","redhat.vscode-yaml"
  ]}}
}
JSON
cat > "${TPL}/Makefile" <<'MK'
NAME?=$(notdir $(CURDIR))
PORT?=$(shell portmap reserve github $(NAME)-web 0 2>/dev/null || echo 0)
APP_PORT?=3000
up:
	@echo "PORT=$(PORT) APP_PORT=$(APP_PORT)"
	@PORT=$(PORT) APP_PORT=$(APP_PORT) docker compose up -d --build
sh:
	docker compose exec app bash || docker compose run --rm app bash
down:
	docker compose down -v
release-port:
	@portmap release $(NAME)-web || true
MK

# ===== Repo-Klonen =====
mkdir -p "${PROJ_DIR}"
pushd "${PROJ_DIR}" >/dev/null
REPO_JSON=$(gh repo list "${GH_USER}" --limit 200 --json name,sshUrl || echo "[]")
echo "${REPO_JSON}" | jq -r '.[] | [.name, .sshUrl] | @tsv' | while IFS=$'\t' read -r NAME SSH; do
  [ -n "${NAME:-}" ] && [ -n "${SSH:-}" ] || continue
  if [ -d "${NAME}/.git" ]; then
    echo "-> ${NAME} vorhanden"
  else
    echo "-> Klone ${NAME}"
    git clone "${SSH}" "${NAME}" || echo "!! Fehler: ${NAME}"
  fi
done
popd >/dev/null

# ===== Alle Repos dockerisieren =====
dockerfile_for_repo() {
  local dir="$1"
  if [ -f "$dir/package.json" ]; then
    cat >"$dir/Dockerfile" <<'NODE'
FROM node:22-bookworm
WORKDIR /work
COPY package*.json . 2>/dev/null || true
RUN npm ci 2>/dev/null || true
CMD ["sleep","infinity"]
NODE
    echo 3000
  elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ]; then
    cat >"$dir/Dockerfile" <<'PY'
FROM python:3.12-slim
WORKDIR /work
COPY requirements.txt . 2>/dev/null || true
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || true
CMD ["sleep","infinity"]
PY
    echo 8000
  elif [ -f "$dir/pom.xml" ]; then
    cat >"$dir/Dockerfile" <<'JAVA'
FROM eclipse-temurin:21-jdk
WORKDIR /work
CMD ["sleep","infinity"]
JAVA
    echo 8080
  else
    cp -n "$TPL/Dockerfile" "$dir/Dockerfile"
    echo 3000
  fi
}

echo "==> Dockerisiere Repos in: $PROJ_DIR"
shopt -s nullglob
for repo in "$PROJ_DIR"/*/ ; do
  [ -d "$repo/.git" ] || continue
  echo "-- $repo"
  APP_PORT=3000
  [ -f "$repo/Dockerfile" ] || APP_PORT=$(dockerfile_for_repo "$repo" || echo 3000)
  [ -f "$repo/docker-compose.yml" ] || cp -n "$TPL/docker-compose.yml" "$repo/docker-compose.yml"
  mkdir -p "$repo/.devcontainer"
  [ -f "$repo/.devcontainer/devcontainer.json" ] || cp -n "$TPL/devcontainer.json" "$repo/.devcontainer/devcontainer.json"
  [ -f "$repo/Makefile" ] || cp -n "$TPL/Makefile" "$repo/Makefile"

  GH_PORT="$(portmap reserve github "$(basename "$repo")-web" 0 2>/dev/null || echo "")"
  {
    echo "APP_PORT=${APP_PORT:-3000}"
    [ -n "$GH_PORT" ] && echo "PORT=${GH_PORT}"
  } > "$repo/.env"

  cat >"$repo/compose.db.example.yml" <<'DBYML'
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app
      POSTGRES_USER: dev
    volumes: [ "pgdata:/var/lib/postgresql/data" ]
    ports: [ "${DB_PORT:-0}:5432" ]
volumes: { pgdata: {} }
DBYML
  echo "# Optional DB starten:
#   export DB_PORT=\$(portmap reserve other $(basename "$repo")-db 0)
#   docker compose -f docker-compose.yml -f compose.db.example.yml up -d
" > "$repo/DB_README.txt"
done

# ===== Abschluss =====
echo
echo "Portainer UI: https://${HOSTNAME_NEW}:${UI_PORT}"
echo "GitHub-Ports: 10000-20000 | Sonstige: 25000-28000"
echo "Projekte:     ${PROJ_DIR}"
echo "Beispiel:     cd ${PROJ_DIR}/<repo> && make up && make sh"
echo "Neue Shell öffnen oder ab-/anmelden, damit Docker-Gruppe aktiv wird."
EOF

chmod +x /tmp/setup_devpc.sh && /tmp/setup_devpc.sh
