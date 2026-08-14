# Plex over Tailscale as a local connection

This project configures a Linux Plex server as a Tailscale subnet router, so your own Tailscale devices can reach Plex through its LAN address while away from home.

It does not patch Plex, bypass authentication, or modify subscriptions. It creates a real private network route. Plex still decides whether a session is local; verify it in the Plex Dashboard (`Local` / `LAN`).

## Requirements

- Linux with systemd
- Tailscale installed, connected, and administered by you
- Plex Media Server reachable on the server
- root access on the Linux server

## Install

```bash
git clone https://github.com/Gionny1294/plex-tailscale-local.git
cd plex-tailscale-local
sudo ./setup.sh
```

You can supply values explicitly:

```bash
sudo ./setup.sh --lan-cidr 192.168.1.0/24 \
  --plex-preferences "/path/to/Preferences.xml"
```

After the script finishes:

1. Open the [Tailscale machines page](https://login.tailscale.com/admin/machines).
2. Find the Plex server and approve the advertised subnet route.
3. Enable Tailscale on the phone.
4. Disable Wi-Fi and test `http://SERVER_LAN_IP:32400/web`.
5. In the Plex app, set home/local streaming quality to Original.

No router port forwarding is required. Tailscale can use a DERP relay when a direct path is unavailable; this may reduce throughput.

## Changes made

- enables and persists IPv4 forwarding;
- advertises the selected LAN subnet through Tailscale;
- adds the LAN subnet and `100.64.0.0/10` to Plex's LAN Networks preference;
- clears Plex custom connections only with `--clear-custom-connections`.

Run `./setup.sh --help` for all options. The script is idempotent.

Use this only for servers and networks you administer. Plex rules and client behavior may change, so local classification cannot be guaranteed forever.

## License

MIT
