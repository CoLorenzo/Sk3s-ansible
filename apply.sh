#!/bin/bash
PLAYBOOK="$1"
if [[ -z "${PLAYBOOK}" ]]; then
    PLAYBOOK="deploy_all.yaml"
fi
echo "running playbook: ${PLAYBOOK}"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ansible-playbook -i inventory-sample.yml ./playbooks/${PLAYBOOK}
CONTROLLER_ADDR=$(yq '.k3s_cluster.children.server.hosts | keys | .[]' inventory-sample.yml)
ansible server -i inventory-sample.yml -m fetch -a "src=/etc/rancher/k3s/k3s.yaml dest=./kube_config.yaml flat=yes"
ssh-agent -k
sed -i "s/127.0.0.1/${CONTROLLER_ADDR}/g" kube_config.yaml
echo "Kubeconfig updated with IP: ${CONTROLLER_ADDR}"
