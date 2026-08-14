#!/usr/bin/env bash
set -euo pipefail

LAN_CIDR=""
PLEX_URL="http://127.0.0.1:32400"
PLEX_PREFERENCES=""
CLEAR_CUSTOM_CONNECTIONS=0

usage() {
  cat <<'EOF'
Usage: sudo ./setup.sh [options]
  --lan-cidr CIDR              LAN subnet (auto-detected by default)
  --plex-url URL               Plex URL (default: http://127.0.0.1:32400)
  --plex-preferences PATH      Plex Preferences.xml containing PlexOnlineToken
  --clear-custom-connections   Clear Plex customConnections
  -h, --help                   Show this help
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --lan-cidr) (($# >= 2)) || die "--lan-cidr requires a value"; LAN_CIDR=$2; shift 2 ;;
    --plex-url) (($# >= 2)) || die "--plex-url requires a value"; PLEX_URL=${2%/}; shift 2 ;;
    --plex-preferences) (($# >= 2)) || die "--plex-preferences requires a value"; PLEX_PREFERENCES=$2; shift 2 ;;
    --clear-custom-connections) CLEAR_CUSTOM_CONNECTIONS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ ${EUID} -eq 0 ]] || die "run this script with sudo"
for command in tailscale systemctl sysctl ip curl sed awk; do
  command -v "$command" >/dev/null || die "missing command: $command"
done

systemctl is-active --quiet tailscaled || die "tailscaled is not running"
tailscale status >/dev/null || die "Tailscale is not connected"

if [[ -z $LAN_CIDR ]]; then
  default_device=$(ip -4 route show default | awk 'NR == 1 {print $5}')
  [[ -n $default_device ]] || die "could not detect the default interface"
  LAN_CIDR=$(ip -4 route show dev "$default_device" proto kernel scope link | awk 'NR == 1 {print $1}')
  [[ -n $LAN_CIDR ]] || die "could not detect the LAN subnet; use --lan-cidr"
fi
[[ $LAN_CIDR == */* ]] || die "invalid LAN CIDR: $LAN_CIDR"

printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/99-plex-tailscale.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null
tailscale set --advertise-routes="$LAN_CIDR"

if [[ -z $PLEX_PREFERENCES ]]; then
  candidates=(
    "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"
    "/config/Library/Application Support/Plex Media Server/Preferences.xml"
  )
  for candidate in "${candidates[@]}"; do
    [[ -r $candidate ]] && { PLEX_PREFERENCES=$candidate; break; }
  done
fi

if [[ -n $PLEX_PREFERENCES && -r $PLEX_PREFERENCES ]]; then
  token=$(sed -n 's/.*PlexOnlineToken="\([^"]*\)".*/\1/p' "$PLEX_PREFERENCES")
  [[ -n $token ]] || die "PlexOnlineToken was not found"
  plex_networks="$LAN_CIDR,100.64.0.0/10"
  curl --fail --silent --show-error -X PUT --get "$PLEX_URL/:/prefs" \
    --data-urlencode "LanNetworksBandwidth=$plex_networks" \
    --data-urlencode "X-Plex-Token=$token" -o /dev/null
  if ((CLEAR_CUSTOM_CONNECTIONS)); then
    curl --fail --silent --show-error -X PUT --get "$PLEX_URL/:/prefs" \
      --data-urlencode 'customConnections=' \
      --data-urlencode "X-Plex-Token=$token" -o /dev/null
  fi
  printf 'Plex LAN Networks configured: %s\n' "$plex_networks"
else
  printf 'Plex preferences not found; subnet routing was configured only.\n'
  printf 'Re-run with --plex-preferences PATH to configure Plex automatically.\n'
fi

printf '\nSubnet advertised: %s\n' "$LAN_CIDR"
printf 'Approve it in Tailscale admin, then test the Plex LAN address.\n'
