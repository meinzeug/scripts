cat >/tmp/setup_devpc.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n==> %s\n" "$*"; }

# ===== Eingaben (mit JSON-Cache) =====
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/dev-first-install"
CONFIG_FILE="${CONFIG_DIR}/user-config.json"

ask() { # ask "Prompt" "default" -> echo answer
  local prompt="$1" default="$2" input
  read -rp "${prompt} [${default}]: " input
  printf '%s' "${input:-$default}"
}

json_get() {
  local key="$1"
  [ -f "$CONFIG_FILE" ] || { echo ""; return; }
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('${key}',''))" "$CONFIG_FILE" 2>/dev/null || echo ""
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k]//""' "$CONFIG_FILE" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  if command -v python3 >/dev/null 2>&1; then
    HOSTNAME_NEW="$HOSTNAME_NEW" GIT_NAME="$GIT_NAME" GIT_EMAIL="$GIT_EMAIL" GH_USER="$GH_USER" PROJ_DIR="$PROJ_DIR" \
    python3 - "$CONFIG_FILE" <<'PY' || true
import json, os, sys
out = sys.argv[1]
data = {
  "hostname": os.environ.get("HOSTNAME_NEW",""),
  "git_name": os.environ.get("GIT_NAME",""),
  "git_email": os.environ.get("GIT_EMAIL",""),
  "gh_user": os.environ.get("GH_USER",""),
  "proj_dir": os.environ.get("PROJ_DIR",""),
}
with open(out, 'w') as f:
  json.dump(data, f, ensure_ascii=False, indent=2)
PY
  else
    cat >"$CONFIG_FILE" <<JSON
{"hostname":"$HOSTNAME_NEW","git_name":"$GIT_NAME","git_email":"$GIT_EMAIL","gh_user":"$GH_USER","proj_dir":"$PROJ_DIR"}
JSON
  fi
}

# Vorbelegte Werte ggf. aus vorhandener Config lesen
HOST_SAVED="$(json_get hostname)"
GIT_NAME_SAVED="$(json_get git_name)"
GIT_EMAIL_SAVED="$(json_get git_email)"
GH_USER_SAVED="$(json_get gh_user)"
PROJ_DIR_SAVED="$(json_get proj_dir)"

if [ -f "$CONFIG_FILE" ]; then
  log "Gespeicherte Angaben gefunden:"
  printf "  Host=%s  Git='%s' <%s>  GH=%s  Projekte=%s\n" \
    "${HOST_SAVED:-}" "${GIT_NAME_SAVED:-}" "${GIT_EMAIL_SAVED:-}" "${GH_USER_SAVED:-}" "${PROJ_DIR_SAVED:-}"
  read -rp "Diese Werte verwenden? [J/n]: " USE_SAVED
  USE_SAVED=${USE_SAVED:-J}
else
  USE_SAVED="n"
fi

if [[ "${USE_SAVED^^}" == J* ]]; then
  HOSTNAME_NEW=${HOST_SAVED:-devpc}
  GIT_NAME=${GIT_NAME_SAVED:-}
  GIT_EMAIL=${GIT_EMAIL_SAVED:-}
  GH_USER=${GH_USER_SAVED:-}
  # Fallback falls proj_dir in alter Config fehlte
  PROJ_DIR=${PROJ_DIR_SAVED:-"${HOME}/Projekte/${GH_USER:-user}"}
else
  HOSTNAME_NEW=$(ask "Hostname" "${HOST_SAVED:-devpc}")
  GIT_NAME=$(ask "Git Benutzername (Voller Name)" "${GIT_NAME_SAVED:-}")
  GIT_EMAIL=$(ask "Git E-Mail" "${GIT_EMAIL_SAVED:-}")
  GH_USER=$(ask "GitHub Username" "${GH_USER_SAVED:-}")
  # Standard hängt von GH_USER ab
  PROJ_DIR_DEFAULT="${PROJ_DIR_SAVED:-${HOME}/Projekte/${GH_USER:-user}}"
  PROJ_DIR=$(ask "Projektverzeichnis" "$PROJ_DIR_DEFAULT")
fi

log "Host=${HOSTNAME_NEW} Git='${GIT_NAME}' <${GIT_EMAIL}> GH=${GH_USER} Projekte=${PROJ_DIR}"
save_config || true

# ===== Hostname =====
log "Hostname setzen"
sudo hostnamectl set-hostname "${HOSTNAME_NEW}"
grep -q "${HOSTNAME_NEW}" /etc/hosts || echo "127.0.1.1 ${HOSTNAME_NEW}" | sudo tee -a /etc/hosts >/dev/null

# ===== Updates + Tools =====
log "System aktualisieren und Basis-Tools installieren"
sudo apt update
sudo apt -y upgrade
sudo apt -y dist-upgrade
sudo apt -y install git make curl wget unzip zip jq ripgrep fzf bat tmux htop build-essential ca-certificates gnupg lsb-release ufw zsh iproute2 software-properties-common
sudo apt -y autoremove && sudo apt -y autoclean

# ===== Docker =====
log "Docker installieren"
sudo apt -y remove docker docker-engine docker.io containerd runc || true
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
UB_CODENAME="$(. /etc/os-release; echo "$UBUNTU_CODENAME")"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UB_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update || true
if ! sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
  log "Fallback: Docker aus Ubuntu-Repo installieren"
  sudo apt -y install docker.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker "$USER" || true

# Docker-Daemon sicher starten
sudo systemctl enable --now docker

# User in Gruppe aufnehmen (idempotent)
sudo usermod -aG docker "$USER"

# Gruppenzugehörigkeit jetzt aktiv machen (ohne Ab-/Anmelden)
newgrp docker

# Test (soll ohne "permission denied" laufen)
docker ps

# Optional: Docker is running
docker run --rm Docker works. 

sudo systemctl enable docker
sudo systemctl enable containerd

# ===== Firewall =====
log "Firewall konfigurieren"
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Einige Systeme haben kein UFW-App-Profil "OpenSSH"
if sudo ufw app list 2>/dev/null | grep -qw OpenSSH; then
  sudo ufw allow OpenSSH
else
  log "UFW-Profil 'OpenSSH' nicht gefunden – erlaube Port 22/tcp direkt"
  sudo ufw allow 22/tcp
fi
# Nicht-interaktiv aktivieren, vermeidet Pipefail/SIGPIPE mit `yes | ...`
sudo ufw --force enable

# ===== GitHub CLI =====
if ! command -v gh >/dev/null 2>&1; then
  log "GitHub CLI installieren"
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt update && sudo apt -y install gh
fi

# ===== Git =====
log "Git konfigurieren"
[ -n "${GIT_NAME}" ]  && git config --global user.name "${GIT_NAME}"
[ -n "${GIT_EMAIL}" ] && git config --global user.email "${GIT_EMAIL}"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "code --wait"
git config --global credential.helper store

# ===== SSH + GitHub Login =====
if [ -n "${GIT_EMAIL}" ] && [ ! -f "${HOME}/.ssh/id_ed25519" ]; then
  mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -C "${GIT_EMAIL}" -f "${HOME}/.ssh/id_ed25519" -N ""
fi
if [ -n "${GH_USER}" ]; then
  gh auth status >/dev/null 2>&1 || gh auth login -w -s "repo,workflow,read:org"
  if [ -f "${HOME}/.ssh/id_ed25519.pub" ]; then
    PUBKEY=$(cat "${HOME}/.ssh/id_ed25519.pub")
    gh ssh-key list --json title,key | jq -e --arg k "$PUBKEY" '[.[]|.key]|index($k) != null' >/dev/null || gh ssh-key add "${HOME}/.ssh/id_ed25519.pub" -t "${HOSTNAME_NEW}"
  fi
fi

# ===== VS Code =====
log "VS Code installieren"
snap list | grep -q "^code " || sudo snap install code --classic
EXTS=( ms-azuretools.vscode-docker ms-vscode-remote.remote-containers github.vscode-pull-request-github
       ms-python.python ms-python.vscode-pylance ms-vscode.cpptools ms-vscode.vscode-typescript-next
       dbaeumer.vscode-eslint esbenp.prettier-vscode redhat.vscode-yaml hashicorp.terraform
       tamasfe.even-better-toml ms-vscode.makefile-tools eamodio.gitlens oderwat.indent-rainbow
       ms-vscode.remote-repositories )
for e in "${EXTS[@]}"; do code --install-extension "$e" >/dev/null || true; done
mkdir -p "${HOME}/.config/Code/User"
cat > "${HOME}/.config/Code/User/settings.json" <<'JSON'
{
  "editor.formatOnSave": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "git.autofetch": true,
  "terminal.integrated.defaultProfile.linux": "zsh",
  "docker.dockerPath": "/usr/bin/docker",
  "remote.containers.dockerPath": "/usr/bin/docker",
  "python.defaultInterpreterPath": "python3",
  "prettier.singleQuote": true,
  "prettier.printWidth": 100
}
JSON

# ===== Portmap =====
log "Portmap installieren"
sudo tee /usr/local/bin/portmap >/dev/null <<'PM'
#!/usr/bin/env bash
set -euo pipefail
DB="${HOME}/.config/portmap/ports.json"
mkdir -p "$(dirname "$DB")"
[ -f "$DB" ] || echo '{"reservations":{}}' > "$DB"
jqset() { TMP="$(mktemp)"; jq "$1" "$DB" > "$TMP" && mv "$TMP" "$DB"; }
in_use() { ss -ltn "( sport = :$1 )" | tail -n +2 | grep -q .; }
range_for(){ case "$1" in github) echo "10000 20000";; other) echo "25000 28000";; *) echo "25000 28000";; esac; }
next_free(){ for ((p=$1;p<=$2;p++)); do in_use "$p"&&continue; jq -e --argjson port "$p" '.reservations|to_entries|map(.value.port)|index($port)!=null' "$DB">/dev/null&&continue; echo "$p";return;done;exit 1;}
case "${1:-}" in
 reserve) typ=$2; name=$3; read s e < <(range_for "$typ"); port=$(next_free $s $e); jqset --arg n "$name" --arg t "$typ" --argjson p "$port" '.reservations[$n]={type:$t,port:$p}'; echo $port;;
 release) name=$2; jqset --arg n "$name" 'del(.reservations[$n])';;
 show) jq . "$DB";;
 *) echo "usage: portmap reserve <github|other> <name> | release <name> | show";;
esac
PM
sudo chmod +x /usr/local/bin/portmap

# ===== Portainer =====
log "Portainer starten"
UI_PORT=$(portmap reserve other portainer-ui)
sudo docker volume create portainer_data >/dev/null
sudo docker rm -f portainer >/dev/null 2>&1 || true
sudo docker run -d -p "${UI_PORT}:9443" --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest


# 1) Tools installieren
sudo apt update
sudo apt -y install mkcert libnss3-tools

# 2) Lokale CA installieren (Root-CA wird in System- und Browser-Truststore eingetragen)
mkcert -install

# 3) Zertifikat für Host und IP erzeugen
HOST=$(hostname -s)
IP=$(hostname -I | awk '{print $1}')
TMPD=$(mktemp -d)
cd "$TMPD"

mkcert -key-file portainer-key.pem -cert-file portainer-cert.pem "$HOST" "$HOST.local" "$IP"

# 4) Zertifikate sicher nach /etc/portainer/certs kopieren
sudo mkdir -p /etc/portainer/certs
sudo install -o root -g root -m 600 portainer-key.pem /etc/portainer/certs/portainer-key.pem
sudo install -o root -g root -m 644 portainer-cert.pem /etc/portainer/certs/portainer-cert.pem

# 5) Port reservieren und Portainer mit SSL starten
portmap release portainer-ui 2>/dev/null || true
UI_PORT=$(portmap reserve other portainer-ui 25443 || echo 25443)
docker rm -f portainer 2>/dev/null || true
docker volume create portainer_data >/dev/null 2>&1 || true

docker run -d \
  -p "${UI_PORT}:9443" \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  -v /etc/portainer/certs:/certs:ro \
  portainer/portainer-ce:latest \
  --sslcert /certs/portainer-cert.pem \
  --sslkey /certs/portainer-key.pem


# ===== Templates =====
log "Devcontainer-Templates"
TPL="${HOME}/.devcontainer-templates"; mkdir -p "$TPL"
cat >"$TPL/Dockerfile" <<'DCK'
FROM debian:stable-slim
RUN apt-get update && apt-get install -y git curl ca-certificates build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /work
CMD ["sleep","infinity"]
DCK
cat >"$TPL/docker-compose.yml" <<'YML'
services:
  app:
    build: .
    command: sleep infinity
    volumes: [ ".:/work" ]
    ports: [ "${PORT:-0}:${APP_PORT:-3000}" ]
YML
cat >"$TPL/devcontainer.json" <<'JSON'
{ "name":"dev","build":{"dockerfile":"../Dockerfile"},"workspaceFolder":"/work"}
JSON
cat >"$TPL/Makefile" <<'MK'
NAME?=$(notdir $(CURDIR))
PORT?=$(shell portmap reserve github $(NAME)-web 0 2>/dev/null || echo 0)
APP_PORT?=3000
up:; PORT=$(PORT) APP_PORT=$(APP_PORT) docker compose up -d --build
sh:; docker compose exec app bash || docker compose run --rm app bash
down:; docker compose down -v
release-port:; portmap release $(NAME)-web || true
MK

# ===== Repos =====
log "Repos klonen"
mkdir -p "${PROJ_DIR}"
if [ -n "${GH_USER}" ]; then
  pushd "${PROJ_DIR}" >/dev/null
  gh repo list "${GH_USER}" --limit 200 --json name,sshUrl | jq -r '.[]|[.name,.sshUrl]|@tsv' | while IFS=$'\t' read -r NAME SSH; do
    [ -d "$NAME/.git" ] || git clone "$SSH" "$NAME"
    cp -n "$TPL"/* "$NAME"/ 2>/dev/null || true
  done
  popd >/dev/null
fi

# ===== Fertig =====
log "Fertig"

UI_PORT=$(portmap reserve other portainer-ui 25443 || echo 25443)
docker rm -f portainer 2>/dev/null || true
docker volume create portainer_data >/dev/null 2>&1 || true
docker run -d -p "${UI_PORT}:9443" --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
  portainer/portainer-ce:latest
echo "Portainer: https://$(hostname -s):${UI_PORT}"


echo "Projekte: ${PROJ_DIR}"
echo "Beispiel: cd ${PROJ_DIR}/<repo> && make up && make sh"
EOF

chmod +x /tmp/setup_devpc.sh && /tmp/setup_devpc.sh
