# talos-cncf-vienna-demo

Two Talos machine config patches that build up one control-plane node into a
self-contained GitOps demo cluster, staged for a CNCF Vienna talk.

- `cncf-vienna-demo/patch-simple.yaml` — stage 1: just the install disk and a VIP.
- `cncf-vienna-demo/patch.yaml` — stage 2, full-featured: everything below.

## What `cncf-vienna-demo/patch.yaml` does

- Sets the install disk (`/dev/sda`)
- Adds a VIP, `10.0.2.100`, on `enp0s3`
- Provisions a second disk (`/dev/sdb`) as a `UserVolumeConfig`, mounted at `/var/mnt/data`
- Runs [`zot`](https://zotregistry.dev) as a static pod in `kube-system`, using that disk for storage
- Points the node's containerd at `zot` as a pull-through mirror for `docker.io`,
  `ghcr.io`, `registry.k8s.io` and `quay.io` — so it's the cluster's default
  container registry
- Enables `allowSchedulingOnControlPlanes`, since this is a one-node cluster
- Bootstraps [Flux](https://fluxcd.io) via a one-shot Helm-install `Job`
  (`cluster.inlineManifests`), then points a Flux `OCIRepository` at
  `oci://10.0.2.100:5000/apps` — the same `zot` registry — with a
  `Kustomization` that reconciles whatever's pushed there

## `apps/`

A minimal Flux-ready kustomization (namespace + [podinfo](https://github.com/stefanprodan/podinfo)
deployment + NodePort service) meant to be pushed to `zot` as an OCI artifact,
which is what the `OCIRepository` above watches:

```bash
# reach zot from your machine, e.g. via port-forward:
kubectl -n kube-system port-forward pod/<zot-pod> 5000:5000 &

tar -czf apps.tar.gz -C apps .
oras push --plain-http 127.0.0.1:5000/apps:latest \
  --artifact-type application/vnd.cncf.flux.config.v1+json \
  apps.tar.gz:application/vnd.cncf.flux.content.v1.tar+gzip
```

Flux polls `OCIRepository/apps` every minute; once it sees a new digest it
reconciles `Kustomization/apps` and `podinfo` shows up in the `demo` namespace
on NodePort `30080`.

## Using it

Generate a full config from a patch and hand it to a node in maintenance mode:

```bash
talosctl gen config talos-cncf-vienna-demo https://10.0.2.100:6443 \
  --output-dir . \
  --config-patch-control-plane @cncf-vienna-demo/patch.yaml

talosctl apply-config --insecure -n <node-ip> --file controlplane.yaml
```

(swap in `patch-simple.yaml` for the stage-1 starting point.)

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
- [x] A simpler, VIP-only variant of this patch as the demo's starting point
- [x] Flux installed via a Talos-managed Helm job
- [x] An `apps/` tree pushed through `zot`, with Flux pointed at it
