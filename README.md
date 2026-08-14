# PlexTailLink

Make Plex feel at home, anywhere, through your private Tailscale network.

This project configures a Linux or Windows Plex server as a Tailscale subnet router, so your own Tailscale devices can reach Plex through its LAN address while away from home.

It does not patch Plex, bypass authentication, or modify subscriptions. It creates a real private network route. Plex still decides whether a session is local; verify it in the Plex Dashboard (`Local` / `LAN`).

## Requirements

- Linux with systemd, or Windows 10 / Windows Server 2016 and later
- Tailscale installed, connected, and administered by you
- Plex Media Server reachable on the server
- root access on the Linux server

## Linux

```bash
git clone https://github.com/Gionny1294/PlexTailLink.git
cd PlexTailLink
sudo ./setup.sh
```

You can supply values explicitly:

```bash
sudo ./setup.sh --lan-cidr 192.168.1.0/24 \
  --plex-preferences "/path/to/Preferences.xml"
```

For Docker installations, the Linux script automatically looks for a running
Plex container and resolves the host directory mounted at `/config`.

## Windows

Open **PowerShell as Administrator**, then run:

```powershell
git clone https://github.com/Gionny1294/PlexTailLink.git
cd PlexTailLink
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

The Windows script detects the LAN and reads the Plex token from the current
user's registry. If Plex runs under another account, use:

```powershell
.\setup.ps1 -LanCidr 192.168.1.0/24 -PlexToken "YOUR_TOKEN"
```

It enables IPv4 forwarding as required by the official [Tailscale Windows subnet router guide](https://tailscale.com/docs/features/subnet-routers?tab=windows).

After the script finishes:

1. Open the [Tailscale machines page](https://login.tailscale.com/admin/machines).
2. Find the Plex server and approve the advertised subnet route.
3. Enable Tailscale on the phone.
4. Disable Wi-Fi and test `http://SERVER_LAN_IP:32400/web`.
5. In the Plex app, set both **Home/Local Streaming** and **Mobile Data/Remote Streaming** quality to **Original/Maximum**. Otherwise Plex may transcode the video and playback can become slow.

No router port forwarding is required. Tailscale can use a DERP relay when a direct path is unavailable; this may reduce throughput.

## Changes made

- enables IPv4 forwarding (and persists it through sysctl on Linux);
- advertises the selected LAN subnet through Tailscale;
- adds the LAN subnet and `100.64.0.0/10` to Plex's LAN Networks preference;
- clears Plex custom connections only with `--clear-custom-connections`.

Run `./setup.sh --help` for all options. The script is idempotent.

Use this only for servers and networks you administer. Plex rules and client behavior may change, so local classification cannot be guaranteed forever.

## License

MIT
