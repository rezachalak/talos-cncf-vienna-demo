# talos-cncf-vienna-demo

A single Talos machine config patch that turns one control-plane node into a
self-contained demo cluster, built for a CNCF Vienna talk.

## What `cncf-vienna-demo/patch.yaml` does

- Sets the install disk (`/dev/sda`)
- Adds a VIP, `10.0.2.100`, on `enp0s3`
- Provisions a second disk (`/dev/sdb`) as a `UserVolumeConfig`, mounted at `/var/mnt/data`
- Runs [`zot`](https://zotregistry.dev) as a static pod in `kube-system`, using that disk for storage
- Points the node's containerd at `zot` as a pull-through mirror for `docker.io`,
  `ghcr.io`, `registry.k8s.io` and `quay.io` — so it's the cluster's default
  container registry
- Enables `allowSchedulingOnControlPlanes`, since this is a one-node cluster

## Using it

Generate a full config from the patch and hand it to a node in maintenance mode:

```bash
talosctl gen config talos-cncf-vienna-demo https://10.0.2.100:6443 \
  --output-dir . \
  --config-patch-control-plane @cncf-vienna-demo/patch.yaml

talosctl apply-config --insecure -n <node-ip> --file controlplane.yaml
```

Already have a running node and just changed the patch? Regenerate against your
existing secrets and push a full replace (avoids `talosctl patch mc`, which
appends rather than replaces list fields like `machine.files`):

```bash
talosctl gen config talos-cncf-vienna-demo https://10.0.2.100:6443 \
  --output-dir . --with-secrets secrets.yaml \
  --config-patch-control-plane @cncf-vienna-demo/patch.yaml --force

talosctl apply-config -n <node-ip> --file controlplane.yaml
```

The `install.image` in the patch points at a Talos Factory image built for one
specific box — swap it for your own (or drop the field and pass `--install-image`
to `gen config` instead).

## Gotchas worth knowing

- **Static pod config files must live where kubelet can see them.** Kubelet on
  Talos runs in its own restricted mount namespace — arbitrary paths under
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

## Roadmap

- [x] VIP + zot as the cluster's default registry mirror
- [ ] A simpler, VIP-only variant of this patch as the demo's starting point
- [ ] Flux installed via a Talos-managed Helm job
- [ ] An `apps/` tree pushed through `zot`, with Flux pointed at it
