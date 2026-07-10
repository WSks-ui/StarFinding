#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 sudo 运行：sudo ./scripts/install.sh" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/opt/starfinding-gateway"
DATA_DIR="/var/lib/starfinding-gateway"

if ! id starfinding >/dev/null 2>&1; then
  useradd --system --home-dir "${DATA_DIR}" --shell /usr/sbin/nologin starfinding
fi

apt-get update
apt-get install -y python3-venv gphoto2 ffmpeg astrometry.net

install -d -o root -g root "${INSTALL_DIR}"
install -d -o starfinding -g starfinding "${DATA_DIR}"
rm -rf "${INSTALL_DIR}/app" "${INSTALL_DIR}/.venv"
cp -a "${SOURCE_DIR}/app" "${INSTALL_DIR}/app"
cp "${SOURCE_DIR}/pyproject.toml" "${SOURCE_DIR}/README.md" "${INSTALL_DIR}/"

python3 -m venv "${INSTALL_DIR}/.venv"
"${INSTALL_DIR}/.venv/bin/pip" install --upgrade pip
"${INSTALL_DIR}/.venv/bin/pip" install "${INSTALL_DIR}"

if [[ ! -f /etc/starfinding-gateway.env ]]; then
  cp "${SOURCE_DIR}/.env.example" /etc/starfinding-gateway.env
  chmod 640 /etc/starfinding-gateway.env
fi
cp "${SOURCE_DIR}/systemd/starfinding-gateway.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now starfinding-gateway.service

echo "安装完成。状态：systemctl status starfinding-gateway"
echo "接口文档：http://<树莓派地址>:8000/docs"
