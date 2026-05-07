#!/bin/bash
set -e

# --- Default ---
NAME="agent-nodes"
VCPU="1"
VRAM="1024Mi"
REPLICAS="1"
IMAGE="docker://quay.io/containerdisks/debian:12"
ARCH="x86_64"
AFFINITY=""

# --- Parsing (getopts) ---
while getopts "n:c:m:r:i:a:f:h" opt; do
  case ${opt} in
    n) NAME=$OPTARG ;;
    c) VCPU=$OPTARG ;;
    m) VRAM=$OPTARG ;;
    r) REPLICAS=$OPTARG ;;
    i) IMAGE=$OPTARG ;;
    a) ARCH=$OPTARG ;;
    f) AFFINITY=$OPTARG ;;
    *) exit 1 ;;
  esac
done

OUTPUT_DIR="./playbooks/files/vms/"
mkdir -p "$OUTPUT_DIR"
PLAYBOOK_PATH="${OUTPUT_DIR}/deploy_${NAME}.yml"

# --- Recupero Dati Dinamici (per scriverli nel playbook) ---
SERVER_URL=$(sk3s ctl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
# Usiamo sudo per il token, dato che siamo sul master
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
MACHINE_TYPE=$([[ "$ARCH" == "arm64" ]] && echo "virt" || echo "q35")

# --- Formattazione Affinity per Ansible ---
AFFINITY_YAML=""
if [[ -n "$AFFINITY" ]]; then
  AFFINITY_YAML="      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:"
  for pair in $AFFINITY; do
    K=$(echo $pair | cut -d'=' -f1)
    V=$(echo $pair | cut -d'=' -f2)
    AFFINITY_YAML="$AFFINITY_YAML
              - key: $K
                operator: In
                values: [\"$V\"]"
  done
fi

# --- Generazione del Playbook ---
cat <<EOF > "$PLAYBOOK_PATH"
---
- name: Deploy ReplicaSet for ${NAME}
  hosts: localhost
  connection: local
  tasks:
    - name: Apply KubeVirt ReplicaSet via kubectl
      shell: |
        sk3s ctl apply -f - <<EKV
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
$(echo "$AFFINITY_YAML")
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
        EKV
EOF

echo "Playbook generato con successo: $PLAYBOOK_PATH"
