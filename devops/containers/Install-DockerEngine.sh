#!/usr/bin/env bash
# ===========================================================================
# Install-DockerEngine.sh — нативный Docker Engine в WSL2 (AR-707, PAT-21)
#
# Stage      : 7
# ADR        : ADR-0016
# Rules      : AR-707 (нативный Engine без Docker Desktop), AR-709 (сеть не
#              поднимается скриптом), AR-201 (удаление файлов запрещено)
#
# Запуск (внутри дистрибутива WSL2, пользователь с sudo):
#   bash devops/containers/Install-DockerEngine.sh
#
# Что делает:
#   1. ставит пакеты из официального репозитория Docker (apt);
#   2. фиксирует каталог данных Docker на /mnt/d/Docker (тома на C: запрещены);
#   3. включает автозапуск демона через systemd (systemd=true в /etc/wsl.conf);
#   4. добавляет текущего пользователя в группу docker;
#   5. проверяет состояние (docker info) без запуска контейнеров.
#
# Скрипт не поднимает сеть и не удаляет данные: при отсутствии доступа к
# репозиторию Docker он завершается с ошибкой, ничего не изменяя.
# ===========================================================================
set -euo pipefail

DOCKER_DATA_ROOT="/mnt/d/Docker"
DAEMON_JSON="/etc/docker/daemon.json"

echo "[INFO] Docker Engine: начало установки (Stage 7)"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# --- 0. предусловия ---
if ! grep -qi 'systemd' /proc/1/comm; then
    echo "[WARN] PID 1 не systemd: включите [boot] systemd=true в /etc/wsl.conf (AR-707)."
fi

if ! mountpoint -q /mnt/d; then
    echo "[FAIL] /mnt/d недоступен: тома Docker должны жить на D:\\Docker (AR-707)."
    exit 20
fi

$SUDO mkdir -p "$DOCKER_DATA_ROOT"

# --- 1. пакеты ---
$SUDO apt-get update
$SUDO apt-get install -y ca-certificates curl gnupg
$SUDO install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

$SUDO apt-get update
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- 2. каталог данных на D:\Docker (AR-707) ---
if [ -f "$DAEMON_JSON" ] && ! grep -q 'data-root' "$DAEMON_JSON"; then
    echo "[INFO] daemon.json существует и будет дополнен ключом data-root."
fi
$SUDO mkdir -p /etc/docker
$SUDO tee "$DAEMON_JSON" > /dev/null <<EOF
{
  "data-root": "${DOCKER_DATA_ROOT}",
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF

# --- 3. демон через systemd ---
$SUDO systemctl enable docker.service docker.socket >/dev/null 2>&1 || true
$SUDO systemctl restart docker.service

# --- 4. доступ пользователя ---
$SUDO usermod -aG docker "$USER" || true

# --- 5. проверка ---
echo "[INFO] docker --version:"
docker --version || { echo "[FAIL] docker CLI недоступен"; exit 10; }

echo "[INFO] docker info (фрагмент):"
$SUDO docker info --format 'Server Version: {{.ServerVersion}}; Driver: {{.Driver}}; Root Dir: {{.DockerRootDir}}' || true

echo "[PASS] Docker Engine установлен; тома — ${DOCKER_DATA_ROOT} (AR-707)."
echo "[NOTE] Перезапуск WSL из Windows: wsl --shutdown (перечитает .wslconfig, AR-703)."
