#!/bin/bash
NAME="samplevm"
VCPU="1"
VRAM="520Mi"
DISK="10Gi"
IMAGE="docker://quay.io/containerdisks/debian:12"
ARCH="x86_64"   # x86_64 | arm64
GPU="no"        # no | <device-name> (e.g. nvidia.com/rtx3090)

SERVER_URL=$(sk3s ctl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(sk3s ctl get secret -n kube-system k3s-server-token -o jsonpath='{.data.token}' | base64 -d)

case "${ARCH}" in
  arm64)   MACHINE_TYPE="virt" ;;
  x86_64)  MACHINE_TYPE="q35"  ;;
esac

GPU_SNIPPET=""
if [[ "${GPU}" != "no" ]]; then
  GPU_SNIPPET="          gpus:
            - name: gpu0
              deviceName: ${GPU}"
fi

cat <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${NAME}
  namespace: default
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: ${NAME}-boot
      spec:
        source:
          registry:
            url: ${IMAGE}
        storage:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${DISK}
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${NAME}
    spec:
      domain:
        machine:
          type: ${MACHINE_TYPE}
        cpu:
          cores: ${VCPU}
        memory:
          guest: ${VRAM}
        devices:
          disks:
            - name: boot
              disk:
                bus: virtio
            - name: cloudinit
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
${GPU_SNIPPET}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: boot
          dataVolume:
            name: ${NAME}-boot
        - name: cloudinit
          cloudInitNoCloud:
            userData: |
              #cloud-config
              runcmd:
                - curl -sfL https://get.k3s.io | K3S_URL=${SERVER_URL} K3S_TOKEN=${TOKEN} sh -
EOF
