#!/bin/bash
set -e

# --- Valori di Default ---
NAME="agent-nodes"
VCPU="1"
VRAM="1024Mi"
REPLICAS="1"
IMAGE="docker://quay.io/containerdisks/debian:12"
ARCH="x86_64"
GPU="no"
AFFINITY=""

usage() {
  echo "Usage: $0 [options]"
  echo "  -n NAME      Nome ReplicaSet (default: $NAME)"
  echo "  -c VCPU      CPU cores (default: $VCPU)"
  echo "  -m VRAM      RAM (default: $VRAM)"
  echo "  -r REPLICAS  Numero di VM (default: $REPLICAS)"
  echo "  -i IMAGE     Image (default: $IMAGE)"
  echo "  -a ARCH      Arch: x86_64 | arm64 (default: $ARCH)"
  echo "  -g GPU       GPU device o 'no' (default: $GPU)"
  echo "  -f AFFINITY  Node Affinity, es: 'key1=val1 key2=val2'"
  echo "  -o OUTPUT    Salva manifest su file"
  exit 1
}

while getopts "n:c:m:r:i:a:g:f:o:h" opt; do
  case ${opt} in
    n) NAME=$OPTARG ;;
    c) VCPU=$OPTARG ;;
    m) VRAM=$OPTARG ;;
    r) REPLICAS=$OPTARG ;;
    i) IMAGE=$OPTARG ;;
    a) ARCH=$OPTARG ;;
    g) GPU=$OPTARG ;;
    f) AFFINITY=$OPTARG ;;
    o) OUTPUT=$OPTARG ;;
    *) usage ;;
  esac
done

OUTPUT="./playbooks/file/manifests/${NAME}.yaml"

# --- Logica Dati Cluster ---
SERVER_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(kubectl get secret -n kube-system k3s-server-token -o jsonpath='{.data.token}' | base64 -d)
MACHINE_TYPE=$([[ "$ARCH" == "arm64" ]] && echo "virt" || echo "q35")

# --- Logica Affinity ---
AFFINITY_SNIPPET=""
if [[ -n "$AFFINITY" ]]; then
  AFFINITY_SNIPPET="      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:"
  for pair in $AFFINITY; do
    KEY=$(echo $pair | cut -d'=' -f1)
    VAL=$(echo $pair | cut -d'=' -f2)
    AFFINITY_SNIPPET="$AFFINITY_SNIPPET
              - key: $KEY
                operator: In
                values:
                - $VAL"
  done
fi

# --- Logica GPU ---
GPU_SNIPPET=""
[[ "$GPU" != "no" ]] && GPU_SNIPPET="          gpus:
            - name: gpu0
              deviceName: ${GPU}"

# --- Generazione YAML ---
read -r -d '' MANIFEST <<EOF || true
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceReplicaSet
metadata:
  name: ${NAME}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      kubevirt.io/vmirs: ${NAME}
  template:
    metadata:
      labels:
        kubevirt.io/vmirs: ${NAME}
    spec:
${AFFINITY_SNIPPET}
      domain:
        machine: { type: ${MACHINE_TYPE} }
        cpu: { cores: ${VCPU} }
        memory: { guest: ${VRAM} }
        devices:
          disks:
            - name: containerdisk
              disk: { bus: virtio }
            - name: cloudinit
              disk: { bus: virtio }
          interfaces:
            - name: default
              masquerade: {}
${GPU_SNIPPET}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: containerdisk
          containerDisk: { image: ${IMAGE} }
        - name: cloudinit
          cloudInitNoCloud:
            userData: |
              #cloud-config
              runcmd:
                - curl -sfL https://get.k3s.io | K3S_URL=${SERVER_URL} K3S_TOKEN=${TOKEN} sh -
EOF

if [[ -n "$OUTPUT" ]]; then
  echo "$MANIFEST" > "$OUTPUT"
  echo "Manifest salvato in $OUTPUT"
else
  echo "$MANIFEST" | kubectl apply -f -
fi
