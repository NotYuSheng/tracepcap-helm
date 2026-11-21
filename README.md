# tracepcap-helm

Helm chart for [TracePcap](https://github.com/NotYuSheng/TracePcap), the offline-capable PCAP
analysis platform. It deploys the same stack as TracePcap's Docker Compose files (nginx frontend,
Spring Boot backend, PostgreSQL, MinIO) onto Kubernetes.

```bash
helm install tracepcap oci://ghcr.io/notyusheng/charts/tracepcap \
  --namespace tracepcap --create-namespace \
  --set backend.llm.baseUrl=http://<inference-host>:1234/v1

kubectl -n tracepcap port-forward svc/tracepcap-frontend 8080:80   # then http://localhost:8080
```

## What gets deployed

| Component  | Kind                      | Notes |
|------------|---------------------------|-------|
| frontend   | Deployment + Service      | nginx serving the UI and proxying `/api`. Stateless, scalable. The only thing to expose. |
| backend    | Deployment (1 replica, `Recreate`) + Service | Spring Boot with tshark, nDPI and Suricata. A single replica on purpose: analysis and the AI job queue run in-process. |
| postgresql | StatefulSet + PVC         | Optional (`postgresql.enabled`); use `externalDatabase` for a managed or operator-run database. |
| minio      | StatefulSet + PVC         | Optional (`minio.enabled`); use `externalS3` for any S3-compatible store. |

The backend creates its bucket on startup, and an init container holds it until the database
and object store accept connections.

## Requirements

- Kubernetes 1.25+, Helm 3.8+ (OCI support)
- A TracePcap release whose images (a) accept `NGINX_BACKEND_URL` and read the resolver from
  `/etc/resolv.conf`, and (b) are tagged with their version on GHCR. The chart's `appVersion`
  names that tag.
- About 3 GiB of allocatable memory with the defaults (the backend's 2 GiB is most of it).

## Configuration

See [`charts/tracepcap/values.yaml`](charts/tracepcap/values.yaml): every value is commented,
and `values.schema.json` rejects typos and bad types at install time. These are the ones you are
most likely to set:

| Value | Default | Purpose |
|-------|---------|---------|
| `backend.llm.baseUrl` | `""` | OpenAI-compatible inference endpoint (Story mode, insights, chat). |
| `backend.llm.model` / `existingSecret` | | Model name; Secret with the API key. |
| `backend.memoryMB` + `backend.resources.limits.memory` | `2048` / `2Gi` | Keep these equal. They drive the JVM heap, the upload cap (16%) and the analysis timeout. |
| `backend.geoForceOffline` | `true` | Geolocation from the bundled MMDB only (no ipinfo.io). |
| `backend.retention.*` | 12 h | Upload retention; `enabled: false` keeps files forever. |
| `backend.extraEnv` | `{}` | Any other backend environment variable, as `NAME: value`. |
| `ingress.*` | disabled | ingress-nginx annotations for large uploads and long requests are preset. |
| `postgresql.enabled` / `externalDatabase.*` | bundled | |
| `minio.enabled` / `externalS3.*` | bundled | |
| `global.imageRegistry` | `""` | Rewrites every image to your registry mirror. |
| `networkPolicy.enabled` | `false` | Ingress only to the frontend; datastores only from the backend. |

[`examples/production.yaml`](examples/production.yaml) shows a production-shaped install.

### Air-gapped installs

TracePcap runs fully offline, and the chart does too:

1. On a connected host, pull and push these images to your internal registry, keeping the
   repository paths: `notyusheng/tracepcap-backend`, `notyusheng/tracepcap-nginx`,
   `library/postgres:15-alpine`, `chainguard/minio:latest`, `library/busybox:1.37`.
2. Download the chart `.tgz` from this repo's GitHub releases (or `helm pull oci://...`).
3. `helm install tracepcap ./tracepcap-<version>.tgz --set global.imageRegistry=<your-registry>`

### Security notes

- The backend's entrypoint starts as root, then drops to an unprivileged user with `gosu`. So
  it meets the `baseline` Pod Security Standard but not `restricted`. Its capabilities are
  limited to the five the entrypoint needs. MinIO and the init container run as non-root with a
  read-only root filesystem.
- Generated PostgreSQL and MinIO passwords persist across upgrades and are kept on uninstall
  (`helm.sh/resource-policy: keep`), as are the PVCs, so a reinstall reattaches to its data.
- Login (Keycloak/OIDC) is not wired up yet: TracePcap compiles auth into the frontend image at
  build time, and no auth-enabled image is published.

## Development

```bash
helm lint charts/tracepcap
helm template t charts/tracepcap | less
ct lint --config ct.yaml --all          # what CI runs, plus `ct install` on kind

# Smoke test against locally built images:
minikube start -p tracepcap-helm --memory=4096 --cpus=4
minikube -p tracepcap-helm image load tracepcap-backend:k8s-test tracepcap-nginx:k8s-test
helm install tp charts/tracepcap -n tracepcap --create-namespace -f examples/minikube-local-images.yaml
helm test tp -n tracepcap
```

Releasing: bump `version` in `Chart.yaml` (and `appVersion` to track a TracePcap release) and
merge to `main`. The release workflow pushes the chart to `oci://ghcr.io/notyusheng/charts` and
attaches the `.tgz` to a GitHub release.

## License

MIT, same as TracePcap.
