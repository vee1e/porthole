<div align="center">

# porthole

**Public https and tcp links for ports on your own VPS. No agent, no account, no tunnel.**

</div>

## What it is

A CLI that turns a port on a server you already own into a real public URL under your own domain.

```bash
$ vps http 3000
https://p3000.example.com  ->  vps:3000
ready: https://p3000.example.com returned 200

press ctrl-c to close
14:22:05  200 GET    3ms  /  122.167.45.21
```

It stays in the foreground like ngrok, prints the requests, and closes the route when you ctrl-c. The difference is what sits behind it: DNS points at your server and a reverse proxy on the server does the work. Nothing runs on your laptop, nothing is tunneled, and there is no third party in the path.

Useful when you want to show someone a dev server, test a webhook against a real hostname, reach a database from a laptop, or give a service a certificate without buying anything.

## What makes it different

| | porthole | ngrok | cloudflared | tailscale funnel |
|---|---|---|---|---|
| Origin | your server | your machine | your machine | your machine or tailnet node |
| Extra network hop | none | edge, then back to origin | edge, then back to origin | coordination server |
| Account required | no | yes | Cloudflare account | Tailscale account |
| Custom domain | yes, yours | paid plan | yes, on your zone | no, ts.net only |
| Raw tcp ports | yes | paid plan | no | no |
| Runs while your laptop is closed | yes, with `-d` | no | no | no |
| Request log at the edge | yes | yes | dashboard | no |

## Requirements

- A Linux server with systemd and ssh access.
- Docker on the server. Managed mode starts its own Caddy container; existing mode reuses one you already run.
- A domain, if you want https. Any DNS provider works. Vercel is automated; everything else is one wildcard record you add yourself.
- Ports 80 and 443 reachable, unless you already have a proxy there.

## Try it

```bash
git clone https://github.com/vee1e/porthole
cd porthole
./install.sh
```

`install.sh` puts the `vps` binary in `~/.local/bin`. It is one Node file with no dependencies.

Then point it at a server, once:

```bash
vps setup --host myvps --domain example.com
```

`--host` is whatever you pass to `ssh`. Managed mode starts a Caddy container on 80 and 443 and opens them in ufw if it is active.

```bash
vps http 3000                  # https://p3000.example.com
vps http 3000 --as api         # https://api.example.com
vps tcp 5432                   # tcp://203.0.113.5:25432
vps http 3000 -d               # leave it up and exit
```

## Commands

| Command | What it does |
|---|---|
| `vps setup --host <ssh>` | Configure a server. Run once per server. |
| `vps http <port>` | Open `https://<name>.<domain>`. Holds the terminal and prints requests. |
| `vps tcp <port>` | Open `tcp://<ip>:<public>`. Same lifecycle. |
| `vps ls` | List every route, including detached ones. |
| `vps rm <name\|port>` | Close a route now. Removes DNS, proxy config, firewall rule, forwarder. |
| `vps clean` | Close routes whose port stopped listening. For crashed sessions. |
| `vps open <name\|port>` | Open the https URL in a browser. |
| `vps doctor` | Check ssh, proxy, DNS, and the public IP. |

Flags: `--as <name>` for the subdomain, `--port <n>` for the public tcp port, `-d` to detach, `--no-wait` to skip the readiness check.

## How it works

1. **DNS.** `vps http` creates an `A` record for the name pointing at your server. With Vercel the CLI calls the API; with any other provider you add one wildcard record at setup and nothing is created per route.
2. **Proxy.** A route block is written to Caddy and Caddy is reloaded. Caddy gets the certificate over HTTP-01, renews it on its own, and proxies to `127.0.0.1:<port>`.
3. **TCP.** A systemd socket unit listens on the public port and forwards to `127.0.0.1:<port>` using `systemd-socket-proxyd`. One unit pair per route.
4. **Lifecycle.** Ctrl-c deletes the record, the block, the rule, and the unit. `vps clean` exists for the cases where the process never got to run cleanup: SIGKILL, a closed terminal, a laptop that died.

## Setup modes

**Managed (default).** `vps setup --host myvps --domain example.com` starts a `vps-caddy` container with `--network host`, config and certificates in `/etc/vps/caddy`, and an import of `sites.caddy`. Use this on a clean server.

**Existing proxy.** If you already run Caddy for other sites, point at it and the CLI reads the mounts instead of starting anything:

```bash
vps setup --host myvps --domain example.com --existing caddy
```

It reads the container's `/etc/caddy/Caddyfile` mount, finds a writable config mount, finds the log mount, and detects whether the container uses the host network. Then it appends one `import` line to your Caddyfile after making a timestamped backup. It does not touch your other site blocks.

On a bridge network, containers cannot reach the host's `127.0.0.1`. The CLI relays loopback-only services through a systemd socket proxy, and adds a ufw rule that lets only the docker subnet reach the proxied port.

**No domain.** `vps setup --host myvps` without `--domain` gives you tcp routes only. Add a domain later by re-running setup.

**Manual DNS.** `--dns manual` tells the CLI not to touch DNS. Add `*.example.com A <ip>` at your provider and every `vps http` name resolves immediately.

## Config

`~/.config/vps/config.json`, written by setup. Server-side state is `/etc/vps/routes.json`.

| Field | Meaning |
|---|---|
| `host` | ssh target |
| `domain` | apex domain for https routes, may be empty |
| `publicIp` | ipv4 the records point at, detected at setup |
| `dns.provider` | `vercel` or `manual` |
| `dns.team` | Vercel team slug, optional |
| `proxy.mode` | `managed` or `existing` |
| `proxy.container` | Caddy container name |
| `proxy.networkMode` | docker network, or `host` |
| `proxy.caddyfile` | host path of the Caddyfile |
| `proxy.sitesDir` | host directory holding the generated route file |
| `proxy.sitesPath` | same file, as Caddy sees it inside the container |
| `proxy.logDir` | host log directory |
| `proxy.logPath` | same directory inside the container |

## Speed

Measured from one laptop, same minute, same client. The origin for porthole was the VPS, which is also where the proxy runs.

| | first byte, new connection | warm request |
|---|---|---|
| ngrok (free) | 0.98 to 1.06 s | 0.79 to 1.01 s |
| porthole | 0.18 to 0.27 s | 0.05 to 0.07 s |

The proxy itself costs under a millisecond. What is left is the round trip from the client to your server, so the numbers move with geography, not with traffic.

## Caveats

- Every route is public and unauthenticated. Anything you publish is one URL away from a scanner. Certificate transparency logs publish new names within seconds and bots do find them.
- TCP routes are raw and open to the entire internet. There is no auth and no TLS.
- One server means one location. A viewer on another continent pays the full distance, where a commercial edge network would meet them closer.
- Names live in public certificate logs forever, even after you close the route.
- After `vps rm`, resolvers may keep the old address for up to the record TTL, usually 60 seconds.

## Non-goals

Not a private network. Not a zero-trust tunnel. Not a load balancer. No auth, no access control, no replay. If you need those, put them in front of the app or use a mesh VPN.

## Uninstall

```bash
vps ls && vps rm <route>     # close what is open
rm ~/.local/bin/vps ~/.config/vps/config.json
```

On the server, remove `/etc/vps` and `docker rm -f vps-caddy` if you used managed mode. In existing mode, delete the import line the CLI added to your Caddyfile.

## License

MIT
