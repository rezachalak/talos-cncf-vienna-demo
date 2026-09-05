# talos-cncf-vienna-demo

**Talos: Immutable, Minimal, Mighty** — running Kubernetes on bare metal with Talos.
CNCF Vienna Meetup, 3 September 2026 · Reza Chalak, DevOps Engineer at ProLion.

📊 **Slides: <https://rezachalak.site/talos-cncf-vienna-sep-2026>**

A one-(or two-)node Talos Kubernetes cluster running in VirtualBox, wired up
as a self-contained GitOps demo for a CNCF Vienna talk: Talos boots, brings
up its own container registry ([zot](https://zotregistry.dev)), installs
[Flux](https://fluxcd.io) on its own, and Flux watches that same registry
for app manifests you push to it.

No cloud, no external registry, no separate GitOps repo to wire up — the
whole demo lives on your laptop.

## What's in here

- `cncf-vienna-demo/create-vm.sh` — spins up a VirtualBox VM (2 CPU, 8GB RAM,
  bridged networking, two disks, Talos ISO attached, ready to boot).
- `cncf-vienna-demo/patch-simple.yaml` — stage 1: just the install disk and a VIP.
- `cncf-vienna-demo/patch.yaml` — stage 2, the full demo: everything below.
- `apps/` — a small [podinfo](https://github.com/stefanprodan/podinfo)
  deployment, meant to be pushed to `zot` as the OCI artifact Flux reconciles.
- `run-sheet.sh` — the live-demo run sheet: every command of the walkthrough in
  order, to copy line by line on stage. See "Running from the run sheet" below —
  it is a script to read, not one to execute.
- `cncf-vienna-slides/` — the talk deck, deployed to the slides link above.

## What `patch.yaml` actually sets up

- The install disk (`/dev/sda`) and a VIP on `enp0s3` (see "Picking your VIP" below)
- A second disk (`/dev/sdb`) as a `UserVolumeConfig`, mounted at `/var/mnt/data`
- `zot` running as a static pod in `kube-system`, using that disk for storage
- containerd on the node pointed at `zot` as a pull-through mirror for
  `docker.io`, `ghcr.io`, `registry.k8s.io` and `quay.io`
- `allowSchedulingOnControlPlanes: true`, so a single-node cluster can actually run workloads
- Flux, installed by a one-shot `helm install` Kubernetes `Job` that Talos
  runs automatically (`cluster.inlineManifests`) — no manual `flux install` needed
- A Flux `OCIRepository` + `Kustomization` pointed at `oci://<VIP>:5000/apps`
  — the same `zot` registry — reconciling every 5 seconds

## Quick start

### 1. Spin up the VM(s)

```bash
cd cncf-vienna-demo
./create-vm.sh cncf-demo-1        # control-plane
./create-vm.sh cncf-demo-2        # optional second VM, as a worker
VBoxManage startvm cncf-demo-1
VBoxManage startvm cncf-demo-2
```

Each VM boots into the Talos ISO in maintenance mode, waiting for a config.

### 2. Pick your VIP (read this — it bit us more than once)

The VM uses **bridged** networking, so it gets a real address on whatever
network your laptop is on — home Wi-Fi, office LAN, or a phone hotspot. The
VIP you put in `patch.yaml` **must fall inside that same subnet**, or it will
simply never be reachable, full stop (this looks like a Talos/VirtualBox
problem but it's just basic IP addressing).

Find your subnet first:

```bash
ip -brief addr show      # e.g. 172.20.10.14/28 → usable range is .1–.14
```

A **phone hotspot is usually a /28** — only 14 usable addresses total. Don't
reuse `10.0.2.100` or `192.168.x.x` values from an old NAT setup; they'll
silently time out on a different network. Pick a free address in your actual
range (a quick way to check what's taken: ping-sweep the subnet, then
`ip neigh show`).

Once you know it, put it everywhere it appears in `patch.yaml` (the `vip.ip`,
the four registry mirror `endpoints`, and the Flux `OCIRepository` URL).

### 3. Generate config and apply it

```bash
talosctl gen secrets                              # once, keep secrets.yaml around

talosctl gen config talos-cncf-vienna-demo https://<VIP>:6443 \
  --output-dir demo-1 \
  --config-patch-control-plane @patch.yaml \
  --with-secrets secrets.yaml \
  --with-docs=false --with-examples=false \
  --with-cluster-discovery=true --force

talosctl apply-config --insecure --nodes <control-plane-ip> --file demo-1/controlplane.yaml
talosctl apply-config --insecure --nodes <worker-ip>        --file demo-1/worker.yaml   # if you have one
```

**Re-applying to an already-installed node?** Drop `--insecure` (it only
works against a node still in maintenance mode, no config yet).

### 4. Bootstrap and grab kubeconfig

```bash
export TALOSCONFIG=demo-1/talosconfig
talosctl config endpoint <VIP>
talosctl config node <VIP>
talosctl bootstrap --nodes <control-plane-ip> --endpoints <control-plane-ip>   # once, ever, per cluster

talosctl kubeconfig kc --force
export KUBECONFIG=kc
kubectl get nodes
```

### 5. Push your first app

```bash
cd .. # repo root — this matters, see the gotcha below
flux push artifact oci://<VIP>:5000/apps:latest \
  --path="./apps" \
  --source="$(git config --get remote.origin.url)" \
  --revision="main@sha1:$(git rev-parse HEAD)" \
  --insecure-registry
```

Flux reconciles every 5 seconds — no `flux reconcile` needed, `podinfo` just
shows up in the `demo` namespace on NodePort `30080` shortly after the push.

**⚠️ The `../apps` trap:** always run `flux push artifact` from the repo root
with `--path="./apps"`. If you `cd` into `cncf-vienna-demo/` first and push
with `--path="../apps"`, the artifact ends up with an entry literally named
`../apps` — Flux refuses to extract that (it's a path-traversal safety
check) and just silently keeps serving whatever it last successfully pulled.
That looks exactly like "my push had no effect," but it's really "my push
never landed."

If a bad push does get stuck like this, Flux backs off and won't retry every
5 seconds anymore — force past it once a good artifact is up:

```bash
flux reconcile source oci apps -n flux-system
flux reconcile kustomization apps -n flux-system
```

## Running from the run sheet

`run-sheet.sh` is the same walkthrough as the Quick start above, condensed into
the exact order it gets performed on stage — plus the read-only `talosctl` calls
the talk uses to show that a Talos node is inspectable without ever opening a
shell:

```bash
talosctl get services      # what's running, per the machine config
talosctl get extensions    # what the Factory image actually shipped
talosctl get disks         # and get mounts / usage --humanize /var/mnt/
talosctl etcd status
talosctl edit machineconfig
```

It also carries the `talosctl upgrade` line, pointed at a Factory installer
image — the A/B partition upgrade, done through the API rather than a package
manager.

**Read it, don't run it.** Despite the `.sh`, it is a run sheet rather than an
executable: it hardcodes a VIP and both DHCP addresses that you have to replace
with your own (see "Picking your VIP"), the two node addresses can only be read
off the VM consoles *after* they boot, and `talosctl edit machineconfig` opens
an interactive editor. Run it top to bottom unattended and it will apply configs
to addresses that aren't yours.

Run the commands from `cncf-vienna-demo/` — `./create-vm.sh` and `@patch.yaml`
are both relative to that directory.

> **⚠️ One line in it will bite you:** the final
> `flux push artifact` uses `--path="../apps"`, which is exactly the trap
> documented above. From `cncf-vienna-demo/` that push lands an artifact entry
> literally named `../apps`, Flux refuses to extract it, and the demo silently
> keeps serving the previous state. Before the talk, either run that last command
> from the repo root with `--path="./apps"`, or fix the line in place.

## Gotchas we hit building this

- **`machine.network.hostname` vs. `HostnameConfig`.** `talosctl gen config`
  always emits a `HostnameConfig { auto: stable }` document by default. Setting
  a static hostname via `machine.network.hostname` *and* leaving that
  auto-document in place causes `apply-config` to reject the whole config with
  a confusing `static hostname is already set` error. Set the hostname on the
  `HostnameConfig` document itself instead (`hostname: my-name`, no `auto` key).

- **Changing the cluster endpoint invalidates every live ServiceAccount
  token.** Talos derives the apiserver's `--service-account-issuer` from
  `cluster.controlPlane.endpoint`. Change that endpoint on a cluster that's
  already bootstrapped (e.g. moving from NAT to bridged networking) and every
  already-minted token — `kube-proxy`, Flux's controllers, anything — starts
  failing with `Unauthorized` until the pods restart and mint a fresh token
  under the new issuer.

- **Static pod config files must live where kubelet can see them.** Kubelet
  on Talos runs in its own restricted mount namespace — arbitrary paths under
  `/var` aren't visible to it. `/var/lib/kubelet/...` and `UserVolumeConfig`
  mounts (`/var/mnt/...`) are; a bare `machine.files` entry dropped elsewhere
  isn't. Don't try to fix that with `machine.kubelet.extraMounts` pointing a
  bind-mount destination at the same path as an existing file — Talos `mkdir`s
  the destination, which fails if a file is already there, and takes kubelet
  (and every static pod, including the API server) down with it.

- **`zot`'s on-demand cache resolves by repository path only** — containerd's
  mirror protocol doesn't tell it which upstream a pull came from. Fine here
  since the demo controls the image names; two mirrored registries with an
  identically-named repo would collide.

- **VirtualBox NAT vs. bridged.** NAT is simpler to set up but the guest's
  internal network is invisible from the host except through explicit
  port-forwarding rules — and even then, `hostip:hostport` with a blank guest
  IP forwards to the guest's *primary DHCP address*, not to a VIP configured
  on the same interface. Bridged networking sidesteps all of that (the VM
  just has a real, directly-reachable address) at the cost of needing a VIP
  that actually fits your current network, per the section above.

## Slides

**<https://rezachalak.site/talos-cncf-vienna-sep-2026>**

One self-contained HTML file — a fixed 1920×1080 stage scaled to the viewport,
with no build step, no framework and no runtime dependencies. Open
`cncf-vienna-slides/talos-cncf-vienna-sep-2026/index.html` in a browser and it
works offline, projector included.

- **Navigate** with arrow keys, click, scroll or swipe. Items on a slide reveal
  one at a time before it advances, so a presentation remote drives the builds
  as well as the slides. Arrow-left walks back through them; the dots jump
  straight to a slide fully built.
- **Edit** in place: press `E` (or click the top-left corner) to toggle inline
  editing. Changes autosave to `localStorage`; `Ctrl`/`Cmd`+`S` exports the
  edited deck as a standalone HTML file.

### How it's deployed

Vercel serves the project's Root Directory (`cncf-vienna-slides`) from `/`, so
the URL path is just the folder layout — the deck sits one level down, which is
what puts it at `/talos-cncf-vienna-sep-2026`:

```
cncf-vienna-slides/                  ← Vercel Root Directory, served at /
├── vercel.json
└── talos-cncf-vienna-sep-2026/      ← served at /talos-cncf-vienna-sep-2026
    ├── index.html
    └── assets/
```

`vercel.json` sets `trailingSlash` so the directory form resolves and the
relative `assets/…` references keep working. Every push to `main` redeploys.

`/` is deliberately left alone — the site root is served from a separate
repository, so this project only ever owns its own subpath.

## Roadmap

- [x] VIP + zot as the cluster's default registry mirror
- [x] A simpler, VIP-only variant of this patch as the demo's starting point
- [x] Flux installed via a Talos-managed Helm job
- [x] An `apps/` tree pushed through `zot`, with Flux pointed at it
- [x] `create-vm.sh` for one-command VirtualBox provisioning
- [x] Bridged networking (real LAN/hotspot address instead of NAT)
- [x] 5-second Flux reconcile interval for fast demo iteration
