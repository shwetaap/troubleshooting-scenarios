#!/bin/bash

##########################################################
#
# Functions for managing NetObserv operator and FlowCollector.
#
##########################################################

set -u

wait_for_cluster_crd() {
  local crd_name="${1}"
  local human="${2:-${crd_name}}"
  local max_wait="${3:-720}"
  local waited=0
  infomsg "Waiting for CRD [${crd_name}] (${human})..."
  while ! ${OC} get crd "${crd_name}" >& /dev/null; do
    if [ "${waited}" -ge "${max_wait}" ]; then
      errormsg "Timeout after ${max_wait}s waiting for CRD [${crd_name}] (${human}). Check the operator Subscription in ${NETOBSERV_OPERATOR_NAMESPACE}."
      exit 1
    fi
    echo -n "."
    sleep 5
    waited=$((waited + 5))
  done
  echo ""
  if ! ${OC} wait --for condition=established "crd/${crd_name}" --timeout=3m; then
    errormsg "CRD [${crd_name}] did not become Established within 3m."
    exit 1
  fi
  infomsg "CRD [${crd_name}] is ready"
}

wait_for_operator_deployment() {
  local max_wait="${NETOBSERV_OPERATOR_WAIT_SECONDS:-720}"
  local waited=0
  local deploy_name="netobserv-controller-manager"

  infomsg "Waiting for deployment/${deploy_name} in [${NETOBSERV_OPERATOR_NAMESPACE}] (up to ${max_wait}s)..."
  while ! ${OC} get "deployment/${deploy_name}" -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o name >/dev/null 2>&1; do
    if [ "${waited}" -ge "${max_wait}" ]; then
      errormsg "Timeout after ${max_wait}s waiting for deployment/${deploy_name} in [${NETOBSERV_OPERATOR_NAMESPACE}]. Check Subscription and InstallPlans."
      exit 1
    fi
    echo -n "."
    sleep 5
    waited=$((waited + 5))
  done
  echo ""
  ${OC} rollout status "deployment/${deploy_name}" -n "${NETOBSERV_OPERATOR_NAMESPACE}" --timeout="${NETOBSERV_OPERATOR_ROLLOUT_TIMEOUT:-600s}"
}

install_netobserv_operator() {
  local catalog_source="${1}"

  if [ "${IS_OPENSHIFT}" == "false" ]; then
    infomsg "Installing NetObserv operator from OperatorHub.io"
    ${OC} apply -f https://operatorhub.io/install/netobserv-operator.yaml
    return
  fi

  local subscription_source subscription_channel subscription_name

  case ${catalog_source} in
    redhat)
      subscription_source="redhat-operators"
      subscription_channel="${NETOBSERV_CHANNEL:-stable}"
      subscription_name="netobserv-operator"
      ;;
    community)
      subscription_source="community-operators"
      subscription_channel="${NETOBSERV_CHANNEL:-community}"
      subscription_name="netobserv-operator"
      ;;
    *)
      subscription_source="${catalog_source}"
      subscription_channel="${NETOBSERV_CHANNEL:-stable}"
      subscription_name="netobserv-operator"
      ;;
  esac

  infomsg "Ensuring namespace [${NETOBSERV_OPERATOR_NAMESPACE}] exists"
  ${OC} create namespace "${NETOBSERV_OPERATOR_NAMESPACE}" --dry-run=client -o yaml | ${OC} apply -f -

  # NetObserv CSV only supports AllNamespaces — do not set targetNamespaces (that selects OwnNamespace).
  infomsg "Ensuring AllNamespaces OperatorGroup in [${NETOBSERV_OPERATOR_NAMESPACE}]"
  cat <<EOM | ${OC} apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: netobserv-operator-group
  namespace: ${NETOBSERV_OPERATOR_NAMESPACE}
spec:
  upgradeStrategy: Default
EOM

  # Recover from a prior failed Subscription/InstallPlan (e.g. UnsupportedOperatorGroup).
  if ${OC} get subscription netobserv-operator -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o name >/dev/null 2>&1; then
    local sub_reason sub_state
    sub_reason="$(${OC} get subscription netobserv-operator -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || true)"
    sub_state="$(${OC} get subscription netobserv-operator -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o jsonpath='{.status.state}' 2>/dev/null || true)"
    if [ "${sub_reason}" = "UnsupportedOperatorGroup" ] || [ "${sub_state}" = "UpgradeFailed" ] || [ "${sub_state}" = "InstallPlanFailed" ]; then
      warnmsg "Removing failed Subscription netobserv-operator (reason=${sub_reason:-unknown}, state=${sub_state:-unknown}) before recreate"
      ${OC} delete subscription netobserv-operator -n "${NETOBSERV_OPERATOR_NAMESPACE}" --ignore-not-found=true --wait=true
      local csv
      csv="$(${OC} get csv -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o name 2>/dev/null | grep netobserv || true)"
      if [ -n "${csv}" ]; then
        echo "${csv}" | while IFS= read -r c; do
          [ -n "${c}" ] && ${OC} delete "${c}" -n "${NETOBSERV_OPERATOR_NAMESPACE}" --ignore-not-found=true --wait=true
        done
      fi
    fi
  fi

  infomsg "Installing NetObserv operator from catalog [${catalog_source}] (source=${subscription_source}, channel=${subscription_channel})"
  cat <<EOM | ${OC} apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: netobserv-operator
  namespace: ${NETOBSERV_OPERATOR_NAMESPACE}
spec:
  channel: ${subscription_channel}
  installPlanApproval: Automatic
  name: ${subscription_name}
  source: ${subscription_source}
  sourceNamespace: openshift-marketplace
EOM
}

install_netobserv_flowcollector() {
  local flowcollector_file="${1}"

  if [ ! -f "${flowcollector_file}" ]; then
    errormsg "FlowCollector manifest not found [${flowcollector_file}]"
    exit 1
  fi

  wait_for_cluster_crd "flowcollectors.flows.netobserv.io" "NetObserv FlowCollector" "${NETOBSERV_CRD_WAIT_SECONDS:-720}"

  infomsg "Ensuring namespace [${NETOBSERV_NAMESPACE}] exists"
  ${OC} create namespace "${NETOBSERV_NAMESPACE}" --dry-run=client -o yaml | ${OC} apply -f -

  infomsg "Applying FlowCollector from [${flowcollector_file}] (Loki via spec.loki.monolithic.installDemoLoki)"
  ${OC} apply -f "${flowcollector_file}"

  infomsg "Waiting for FlowCollector/cluster to become Ready (timeout=${NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT:-10m})"
  if ! ${OC} wait flowcollector/cluster --for=condition=Ready --timeout="${NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT:-10m}"; then
    errormsg "FlowCollector/cluster did not become Ready in time"
    ${OC} get flowcollector cluster -o yaml 2>/dev/null | tail -40 || true
    exit 1
  fi
}

validate_netobserv_ready() {
  local ready_status
  ready_status="$(${OC} get flowcollector cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [ "${ready_status}" != "True" ]; then
    errormsg "FlowCollector/cluster Ready=${ready_status:-<missing>}"
    exit 1
  fi

  infomsg "FlowCollector/cluster is Ready"
  ${OC} get flowcollector cluster -o wide 2>/dev/null || true
  ${OC} get pods -n "${NETOBSERV_NAMESPACE}" 2>/dev/null || true
}

delete_netobserv_flowcollector() {
  infomsg "Deleting FlowCollector/cluster (operator-managed demo Loki is removed with it)"
  ${OC} delete flowcollector cluster --ignore-not-found=true --wait=false
}

delete_netobserv_operator() {
  if [ "${IS_OPENSHIFT}" == "false" ]; then
    infomsg "Deleting NetObserv operator subscription (OperatorHub install)"
    ${OC} delete -f https://operatorhub.io/install/netobserv-operator.yaml --ignore-not-found=true || true
    return
  fi

  infomsg "Deleting NetObserv operator Subscription in [${NETOBSERV_OPERATOR_NAMESPACE}]"
  ${OC} delete subscription netobserv-operator -n "${NETOBSERV_OPERATOR_NAMESPACE}" --ignore-not-found=true

  local csv
  csv="$(${OC} get csv -n "${NETOBSERV_OPERATOR_NAMESPACE}" -o name 2>/dev/null | grep netobserv || true)"
  if [ -n "${csv}" ]; then
    infomsg "Deleting CSV(s): ${csv}"
    echo "${csv}" | while IFS= read -r c; do
      [ -n "${c}" ] && ${OC} delete "${c}" -n "${NETOBSERV_OPERATOR_NAMESPACE}" --ignore-not-found=true
    done
  fi

  if [ "${NETOBSERV_DELETE_OPERATOR_NAMESPACE:-}" = "yes" ]; then
    infomsg "Deleting operator namespace [${NETOBSERV_OPERATOR_NAMESPACE}]"
    ${OC} delete namespace "${NETOBSERV_OPERATOR_NAMESPACE}" --ignore-not-found=true --wait=false
  fi
}

status_netobserv() {
  echo ""
  echo "=== NetObserv operator (${NETOBSERV_OPERATOR_NAMESPACE}) ==="
  ${OC} get subscription,csv,deployment -n "${NETOBSERV_OPERATOR_NAMESPACE}" 2>/dev/null || true
  echo ""
  echo "=== Loki (${NETOBSERV_NAMESPACE}, operator-managed) ==="
  ${OC} get pods,svc -n "${NETOBSERV_NAMESPACE}" -l app=loki 2>/dev/null || true
  echo ""
  echo "=== FlowCollector ==="
  ${OC} get flowcollector -A 2>/dev/null || true
  ${OC} get flowcollector cluster -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}' 2>/dev/null || true
  echo ""
  echo "=== NetObserv pipeline pods (${NETOBSERV_NAMESPACE}) ==="
  ${OC} get pods -n "${NETOBSERV_NAMESPACE}" 2>/dev/null || true
}
