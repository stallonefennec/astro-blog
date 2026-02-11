#!/usr/bin/env bash
set -euo pipefail
IFS=$' \t'

readonly SWAP_FILE="/swapfile"
readonly SWAP_SIZE_GB=2
readonly OPENCLAW_DIR="${HOME}/.openclaw"
readonly OPENCLAW_BIN_DIR="${OPENCLAW_DIR}/bin"
readonly CADDY_CACHE_BIN="${OPENCLAW_BIN_DIR}/caddy"
readonly CADDY_BIN="/usr/bin/caddy"
readonly CADDYFILE="/etc/caddy/Caddyfile"
readonly CADDY_USER="caddy"
readonly CADDY_HOME="/var/lib/caddy"
readonly CADDY_WEBROOT="/var/www/html"
readonly CADDY_SERVICE_FILE="/etc/systemd/system/caddy.service"
readonly CADDY_LOG_FILE="/var/log/caddy/access.log"
readonly APPS_BASE_DIR="${OPENCLAW_DIR}/apps"

BACKUP_REPO_OWNER="${BACKUP_REPO_OWNER:-}"
BACKUP_REPO_NAME="${BACKUP_REPO_NAME:-}"
BACKUP_FILE="${BACKUP_FILE:-miya_full_backup_latest.tar.gz}"
DOMAIN="${DOMAIN:-}"
NAIVE_USER="${NAIVE_USER:-naive}"
NAIVE_PASS="${NAIVE_PASS:-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "${OPENCLAW_BIN_DIR}" "${APPS_BASE_DIR}" "${CADDY_WEBROOT}"
}

get_ssh_port() {
  local port
  port="$(ss -tlnp | awk '/sshd/ {split($4,a,":"); print a[length(a)]}' | head -n1 || true)"
  echo "${port:-22}"
}

get_base_domain() {
  local input="$1"
  if [[ "${input}" == *.*.* ]]; then
    echo "${input#*.}"
  else
    echo "${input}"
  fi
}

module_a1_swap() {
  log "A1: Checking swap space..."
  if swapon --show | grep -q "${SWAP_FILE}"; then
    log "Swap already enabled. Skipping."
    return 0
  fi

  local ram_mb
  ram_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
  log "Total RAM: ${ram_mb}MB. Creating ${SWAP_SIZE_GB}GB swap..."

  if [[ ! -f "${SWAP_FILE}" ]]; then
    if ! fallocate -l "${SWAP_SIZE_GB}G" "${SWAP_FILE}"; then
      warn "fallocate failed, falling back to dd..."
      dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    fi
  fi

  chmod 600 "${SWAP_FILE}"
  mkswap "${SWAP_FILE}" >/dev/null
  swapon "${SWAP_FILE}"

  if ! grep -qE '^/swapfile\s' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  swapon --show | grep -q "${SWAP_FILE}" && log "Swap enabled successfully."
}

module_a2_dependencies() {
  log "A2: Installing core dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    curl wget jq git ca-certificates ufw build-essential libcap2-bin \
    gnupg lsb-release tar xz-utils

  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker via official script..."
    curl -fsSL https://get.docker.com | sh
  else
    log "Docker already installed."
  fi

  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin || warn "docker-compose-plugin install skipped/failure."
  fi

  if [[ ! -d /usr/local/nvm ]]; then
    log "Installing NVM + Node.js LTS..."
    export NVM_DIR=/usr/local/nvm
    mkdir -p "${NVM_DIR}"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    # shellcheck source=/dev/null
    source /usr/local/nvm/nvm.sh
    nvm install --lts
    nvm alias default 'lts/*'
  else
    log "NVM already installed."
  fi
}

module_a3_firewall() {
  log "A3: Configuring UFW firewall..."
  local ssh_port
  ssh_port="$(get_ssh_port)"

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "${ssh_port}/tcp" comment 'SSH detected port'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'

  local ports=(3000 5001 3001 8080 9090 12138)
  for p in "${ports[@]}"; do
    ufw allow "${p}/tcp" comment "Docker app ${p}"
  done

  ufw --force enable
  ufw status verbose
}

install_go_1_22_5() {
  local version="1.22.5"
  local arch
  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) err "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac

  if [[ -x /usr/local/go/bin/go ]] && /usr/local/go/bin/go version | grep -q "go${version}"; then
    log "Go ${version} already installed."
    return
  fi

  log "Installing Go ${version} (${arch})..."
  local tarball="go${version}.linux-${arch}.tar.gz"
  curl -fsSL "https://go.dev/dl/${tarball}" -o "/tmp/${tarball}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${tarball}"
  rm -f "/tmp/${tarball}"
}

build_caddy_with_naive() {
  install_go_1_22_5
  export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"

  log "Installing xcaddy..."
  /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

  log "Building Caddy with forwardproxy@naive (this may take ~10 mins)..."
  local build_dir
  build_dir="$(mktemp -d)"
  pushd "${build_dir}" >/dev/null
  "${HOME}/go/bin/xcaddy" build --with github.com/caddyserver/forwardproxy@naive
  popd >/dev/null

  install -m 755 "${build_dir}/caddy" "${CADDY_BIN}"
  install -m 755 "${build_dir}/caddy" "${CADDY_CACHE_BIN}"
  rm -rf "${build_dir}"
}

module_b1_prepare_caddy() {
  log "B1: Preparing Caddy binary..."
  if [[ -x "${CADDY_CACHE_BIN}" ]] && "${CADDY_CACHE_BIN}" list-modules | grep -q 'http.handlers.forward_proxy'; then
    log "Using cached Caddy binary from ${CADDY_CACHE_BIN}."
    install -m 755 "${CADDY_CACHE_BIN}" "${CADDY_BIN}"
    return
  fi

  if [[ -x "${CADDY_CACHE_BIN}" ]]; then
    warn "Cached binary missing naive module. Rebuilding..."
  fi

  build_caddy_with_naive
}

module_b2_setcap() {
  log "B2: Granting cap_net_bind_service to Caddy binary..."
  setcap 'cap_net_bind_service=+ep' "${CADDY_BIN}"
}

module_b3_generate_caddyfile() {
  log "B3: Generating Caddyfile..."
  if [[ -f "${CADDYFILE}" ]] && grep -q 'forward_proxy' "${CADDYFILE}"; then
    log "Existing Caddyfile with forward_proxy detected. Skipping overwrite."
    return
  fi

  if [[ -z "${DOMAIN}" ]]; then
    err "DOMAIN is required to generate Caddyfile. Example: export DOMAIN=mem.example.com"
    exit 1
  fi

  cat > "${CADDYFILE}" <<CFG
{
	order forward_proxy before file_server
	admin off
	log {
		output file ${CADDY_LOG_FILE}
		format json
	}
}

:443, ${DOMAIN} {
	tls {
		protocols tls1.2 tls1.3
		ciphers TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256
	}

	forward_proxy {
		basic_auth ${NAIVE_USER} ${NAIVE_PASS}
		hide_ip
		hide_via
		probe_resistance
	}

	root * ${CADDY_WEBROOT}
	file_server
}
CFG

  chmod 644 "${CADDYFILE}"
  echo 'It works!' > "${CADDY_WEBROOT}/index.html"
}

module_b4_systemd_service() {
  log "B4: Configuring Caddy systemd service..."

  if ! id -u "${CADDY_USER}" >/dev/null 2>&1; then
    useradd --system --home "${CADDY_HOME}" --create-home --shell /usr/sbin/nologin "${CADDY_USER}"
  fi

  chown -R "${CADDY_USER}:${CADDY_USER}" "${CADDY_HOME}" /etc/caddy "${CADDY_WEBROOT}"
  mkdir -p "$(dirname "${CADDY_LOG_FILE}")"
  touch "${CADDY_LOG_FILE}"
  chown "${CADDY_USER}:${CADDY_USER}" "${CADDY_LOG_FILE}"

  cat > "${CADDY_SERVICE_FILE}" <<SERVICE
[Unit]
Description=Caddy with NaiveProxy
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=${CADDY_USER}
Group=${CADDY_USER}
ExecStart=${CADDY_BIN} run --environ --config ${CADDYFILE}
ExecReload=${CADDY_BIN} reload --config ${CADDYFILE}
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now caddy
  sleep 2
  if ! systemctl is-active --quiet caddy; then
    err "Caddy failed to start. Check logs: journalctl -u caddy"
    exit 1
  fi
  log "Caddy service started successfully."
}

ask_github_pat() {
  if [[ -z "${GITHUB_PAT:-}" ]]; then
    read -rs -p 'Enter GitHub PAT: ' GITHUB_PAT
    echo
  fi
}

module_c1_restore_backup() {
  log "C1: Restoring backup from GitHub..."

  if [[ -z "${BACKUP_REPO_OWNER}" || -z "${BACKUP_REPO_NAME}" ]]; then
    warn "BACKUP_REPO_OWNER or BACKUP_REPO_NAME not set. Skipping restore."
    return 0
  fi

  ask_github_pat

  local tmpdir download_file api_url asset_url raw_url
  tmpdir="$(mktemp -d)"
  download_file="${tmpdir}/${BACKUP_FILE}"
  api_url="https://api.github.com/repos/${BACKUP_REPO_OWNER}/${BACKUP_REPO_NAME}/releases/latest"

  asset_url="$(curl -fsSL -H "Authorization: token ${GITHUB_PAT}" "${api_url}" | jq -r --arg f "${BACKUP_FILE}" '.assets[]? | select(.name==$f) | .url' || true)"

  if [[ -n "${asset_url}" && "${asset_url}" != "null" ]]; then
    log "Downloading backup from latest release asset..."
    curl -fsSL \
      -H "Authorization: token ${GITHUB_PAT}" \
      -H 'Accept: application/octet-stream' \
      "${asset_url}" -o "${download_file}"
  else
    warn "Release asset not found. Falling back to raw file from main branch..."
    raw_url="https://raw.githubusercontent.com/${BACKUP_REPO_OWNER}/${BACKUP_REPO_NAME}/main/${BACKUP_FILE}"
    curl -fsSL -H "Authorization: token ${GITHUB_PAT}" "${raw_url}" -o "${download_file}"
  fi

  if [[ ! -s "${download_file}" ]]; then
    err "Backup file download failed or file is empty."
    rm -rf "${tmpdir}"
    exit 1
  fi

  log "Extracting backup into HOME=${HOME} ..."
  tar -xzpf "${download_file}" -C "${HOME}"
  rm -rf "${tmpdir}"
  log "Backup restore completed."
}

inject_reverse_proxy() {
  local subdomain="$1"
  local port="$2"

  if [[ -z "${DOMAIN}" ]]; then
    err "DOMAIN is required for reverse proxy injection."
    exit 1
  fi

  local base_domain fqdn
  base_domain="$(get_base_domain "${DOMAIN}")"
  fqdn="${subdomain}.${base_domain}"

  if grep -q "${fqdn}" "${CADDYFILE}"; then
    log "Reverse proxy for ${fqdn} already exists. Skipping."
    return
  fi

  cat >> "${CADDYFILE}" <<CFG

${fqdn} {
	reverse_proxy localhost:${port}
	tls {
		protocols tls1.2 tls1.3
	}
}
CFG

  log "Injected reverse proxy: ${fqdn} -> localhost:${port}"
}

deploy_docker_app() {
  local app_name="$1"
  local image="$2"
  local host_port="$3"
  local container_port="$4"
  local subdomain="$5"
  local extra_opts="${6:-}"

  local data_dir="${APPS_BASE_DIR}/${app_name}"
  mkdir -p "${data_dir}"

  if docker ps -a --format '{{.Names}}' | grep -qx "${app_name}"; then
    docker rm -f "${app_name}" >/dev/null
  fi

  # shellcheck disable=SC2086
  docker run -d \
    --name "${app_name}" \
    --restart unless-stopped \
    -p "127.0.0.1:${host_port}:${container_port}" \
    -v "${data_dir}:/data" \
    ${extra_opts} \
    "${image}" >/dev/null

  inject_reverse_proxy "${subdomain}" "${host_port}"
  "${CADDY_BIN}" reload --config "${CADDYFILE}"
  log "Deployed ${app_name} on 127.0.0.1:${host_port}"
}

deploy_blinko() {
  log "Deploying Blinko (special dual-container setup)..."
  local data_dir="${APPS_BASE_DIR}/blinko"
  mkdir -p "${data_dir}/pgdata"

  docker network inspect blinko-net >/dev/null 2>&1 || docker network create blinko-net >/dev/null

  docker rm -f blinko-postgres blinko >/dev/null 2>&1 || true

  docker run -d \
    --name blinko-postgres \
    --restart unless-stopped \
    --network blinko-net \
    -e POSTGRES_DB=blinko \
    -e POSTGRES_USER=blinko \
    -e POSTGRES_PASSWORD=blinko_secure_pwd_2024 \
    -v "${data_dir}/pgdata:/var/lib/postgresql/data" \
    postgres:16-alpine >/dev/null

  sleep 5

  local base_domain
  base_domain="$(get_base_domain "${DOMAIN}")"
  local nextauth_secret
  nextauth_secret="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"

  docker run -d \
    --name blinko \
    --restart unless-stopped \
    --network blinko-net \
    -p 127.0.0.1:12138:3000 \
    -e DATABASE_URL='postgresql://blinko:blinko_secure_pwd_2024@blinko-postgres:5432/blinko' \
    -e NEXTAUTH_SECRET="${nextauth_secret}" \
    -e NEXT_PUBLIC_BASE_URL="https://blinko.${base_domain}" \
    blinkospace/blinko:latest >/dev/null

  inject_reverse_proxy "blinko" "12138"
  "${CADDY_BIN}" reload --config "${CADDYFILE}"
  log "Blinko deployed successfully."
}

app_store_menu() {
  while true; do
    cat <<'MENU'
╔══════════════════════════════════════════╗
║        App Store (Docker Ecosystem)      ║
╠══════════════════════════════════════════╣
║  1)  Memos          (note.*)             ║
║  2)  Vaultwarden    (pass.*)             ║
║  3)  Uptime Kuma    (status.*)           ║
║  4)  Stirling-PDF   (pdf.*)              ║
║  5)  Linkding       (link.*)             ║
║  6)  IT-Tools       (tools.*)            ║
║  7)  Blinko         (blinko.*)           ║
║  8)  Deploy ALL Apps                     ║
║  0)  Back to Main Menu                   ║
╚══════════════════════════════════════════╝
MENU

    read -rp 'Select app option [0-8]: ' choice
    case "${choice}" in
      1) deploy_docker_app memos neosmemo/memos:stable 5230 5230 note ;;
      2) deploy_docker_app vaultwarden vaultwarden/server:latest 8880 80 pass ;;
      3) deploy_docker_app uptime-kuma louislam/uptime-kuma:1 3001 3001 status ;;
      4) deploy_docker_app stirling-pdf frooodle/s-pdf:latest 8080 8080 pdf ;;
      5) deploy_docker_app linkding sissbruecker/linkding:latest 9090 9090 link ;;
      6) deploy_docker_app it-tools corentinth/it-tools:latest 8888 80 tools ;;
      7) deploy_blinko ;;
      8)
        deploy_docker_app memos neosmemo/memos:stable 5230 5230 note
        deploy_docker_app vaultwarden vaultwarden/server:latest 8880 80 pass
        deploy_docker_app uptime-kuma louislam/uptime-kuma:1 3001 3001 status
        deploy_docker_app stirling-pdf frooodle/s-pdf:latest 8080 8080 pdf
        deploy_docker_app linkding sissbruecker/linkding:latest 9090 9090 link
        deploy_docker_app it-tools corentinth/it-tools:latest 8888 80 tools
        deploy_blinko
        ;;
      0) break ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

show_system_status() {
  log "===== System Status ====="
  echo "Hostname: $(hostname)"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo "Swap:"
  swapon --show || true
  echo "Docker: $(docker --version 2>/dev/null || echo 'not installed')"
  echo "Caddy: $(${CADDY_BIN} version 2>/dev/null || echo 'not installed')"
  echo "UFW status:"
  ufw status | sed 's/^/  /' || true
}

module_a() {
  module_a1_swap
  module_a2_dependencies
  module_a3_firewall
}

module_b() {
  module_b1_prepare_caddy
  module_b2_setcap
  module_b3_generate_caddyfile
  module_b4_systemd_service
}

module_d() {
  app_store_menu
}

full_system_setup() {
  module_a
  module_b
}

full_deploy() {
  log "Running Full Deploy in optimized order: A -> C -> B -> D"
  module_a
  module_c1_restore_backup
  module_b
  module_d
}

main_menu() {
  while true; do
    cat <<'MENU'
╔══════════════════════════════════════════════════════════════╗
║           Miya VPS Ultimate Master v7.1                     ║
║           Industrial-Grade Self-Healing Framework           ║
╚══════════════════════════════════════════════════════════════╝

Layer 1: Core Operations
  1)  Full System Setup (A+B combined)
  2)  Module A: System Hardening Only
  3)  Module B: Caddy/NaiveProxy Only
  4)  Module C: Soul Injection (Restore Backup)

Layer 2: Application Layer
  5)  Module D: App Store

Utilities
  6)  Show System Status
  7)  Full Deploy (A+B+C+D)
  0)  Exit
MENU

    read -rp 'Select option [0-7]: ' choice
    case "${choice}" in
      1) full_system_setup ;;
      2) module_a ;;
      3) module_b ;;
      4) module_c1_restore_backup ;;
      5) module_d ;;
      6) show_system_status ;;
      7) full_deploy ;;
      0) log 'Bye.'; exit 0 ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

main() {
  require_root
  ensure_dirs
  main_menu
}

main "$@"
