#!/bin/bash

##########################################################
#
# Installs NetObserv operator and eval FlowCollector.
#
##########################################################

set -u

SCRIPT_ROOT="$( cd "$(dirname "$0")" ; pwd -P )"
cd "${SCRIPT_ROOT}"

source "${SCRIPT_ROOT}/func-log.sh"
source "${SCRIPT_ROOT}/func-netobserv.sh"

netobserv_install_require_opt_value() {
  local flag="$1"
  local val="${2:-}"
  if [ -z "${val}" ] || [ "${val#-}" != "${val}" ]; then
    errormsg "Option [${flag}] requires a value. The next argument is missing or starts with '-'."
    exit 1
  fi
}

DEFAULT_OC="oc"
DEFAULT_CATALOG_SOURCE="redhat"
DEFAULT_NETOBSERV_NAMESPACE="netobserv"
DEFAULT_NETOBSERV_OPERATOR_NAMESPACE="openshift-netobserv-operator"
DEFAULT_FLOWCOLLECTOR_FILE="${SCRIPT_ROOT}/../flowcollector.yaml"

_CMD=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in

    install)              _CMD="install"              ; shift ;;
    install-operator)     _CMD="install-operator"     ; shift ;;
    install-flowcollector) _CMD="install-flowcollector" ; shift ;;
    delete-operator)      _CMD="delete-operator"      ; shift ;;
    delete-flowcollector) _CMD="delete-flowcollector" ; shift ;;
    status)               _CMD="status"               ; shift ;;

    -c|--client)                    netobserv_install_require_opt_value "${key}" "${2:-}"; OC="${2}" ; shift;shift ;;
    -cs|--catalog-source)           netobserv_install_require_opt_value "${key}" "${2:-}"; CATALOG_SOURCE="${2}" ; shift;shift ;;
    -ch|--channel)                   netobserv_install_require_opt_value "${key}" "${2:-}"; NETOBSERV_CHANNEL="${2}" ; shift;shift ;;
    -fc|--flowcollector-file)        netobserv_install_require_opt_value "${key}" "${2:-}"; FLOWCOLLECTOR_FILE="${2}" ; shift;shift ;;
    -ns|--namespace)                 netobserv_install_require_opt_value "${key}" "${2:-}"; NETOBSERV_NAMESPACE="${2}" ; shift;shift ;;
    -ons|--operator-namespace)       netobserv_install_require_opt_value "${key}" "${2:-}"; NETOBSERV_OPERATOR_NAMESPACE="${2}" ; shift;shift ;;
    -don|--delete-operator-namespace) NETOBSERV_DELETE_OPERATOR_NAMESPACE="yes" ; shift ;;

    -h|--help)
      cat <<HELPMSG

$0 [option...] command

Installs NetObserv for troubleshooting eval scenarios.

Commands:
  install                 Install operator and eval FlowCollector (full setup)
  install-operator        Install only the NetObserv operator (OLM on OpenShift)
  install-flowcollector   Apply eval FlowCollector and wait for Ready
  delete-flowcollector    Delete FlowCollector/cluster
  delete-operator         Remove operator Subscription/CSV
  status                  Show operator, Loki, and FlowCollector status

Options:
  -c|--client <path>              oc/kubectl client (default: ${DEFAULT_OC})
  -cs|--catalog-source <name>      redhat | community (OpenShift only; default: ${DEFAULT_CATALOG_SOURCE})
  -ch|--channel <name>             OLM channel (default: stable for redhat, community for community)
  -fc|--flowcollector-file <path>  FlowCollector manifest (default: build/flowcollector.yaml)
  -ns|--namespace <name>           NetObserv pipeline namespace (default: ${DEFAULT_NETOBSERV_NAMESPACE})
  -ons|--operator-namespace <name> Operator namespace (default: ${DEFAULT_NETOBSERV_OPERATOR_NAMESPACE})
  -don|--delete-operator-namespace With delete-operator: also delete the operator namespace

Environment:
  NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT   oc wait timeout (default: 10m)
  NETOBSERV_OPERATOR_WAIT_SECONDS        Seconds to wait for operator deployment (default: 720)

HELPMSG
      exit 0
      ;;

    *)
      errormsg "Unknown argument [${key}]. See --help."
      exit 1
      ;;
  esac
done

OC="${OC:-${DEFAULT_OC}}"
CATALOG_SOURCE="${CATALOG_SOURCE:-${DEFAULT_CATALOG_SOURCE}}"
NETOBSERV_NAMESPACE="${NETOBSERV_NAMESPACE:-${DEFAULT_NETOBSERV_NAMESPACE}}"
NETOBSERV_OPERATOR_NAMESPACE="${NETOBSERV_OPERATOR_NAMESPACE:-${DEFAULT_NETOBSERV_OPERATOR_NAMESPACE}}"
FLOWCOLLECTOR_FILE="${FLOWCOLLECTOR_FILE:-${DEFAULT_FLOWCOLLECTOR_FILE}}"

if [ -z "${_CMD}" ]; then
  errormsg "Missing command. See --help."
  exit 1
fi

if ! command -v "${OC}" >/dev/null 2>&1; then
  errormsg "Client not found [${OC}]. Use --client to set oc or kubectl."
  exit 1
fi

if ${OC} api-resources --api-group=route.openshift.io -o name 2>/dev/null | grep -q .; then
  IS_OPENSHIFT="true"
else
  IS_OPENSHIFT="false"
fi

if [ "${IS_OPENSHIFT}" = "true" ]; then
  if ! ${OC} whoami >& /dev/null; then
    errormsg "Not logged in. Run '${OC} login' and retry."
    exit 1
  fi
elif [ "$(basename -- "${OC}")" = "oc" ]; then
  if ! ${OC} whoami >& /dev/null; then
    errormsg "Not logged in. Run '${OC} login' and retry."
    exit 1
  fi
fi

if [ "${IS_OPENSHIFT}" = "true" ] && [ "${CATALOG_SOURCE}" != "redhat" ] && [ "${CATALOG_SOURCE}" != "community" ]; then
  warnmsg "Catalog source [${CATALOG_SOURCE}] is not redhat or community; using it as a custom marketplace source name."
fi

case "${_CMD}" in
  install-operator)
    install_netobserv_operator "${CATALOG_SOURCE}"
    wait_for_cluster_crd "flowcollectors.flows.netobserv.io" "NetObserv FlowCollector" "${NETOBSERV_CRD_WAIT_SECONDS:-720}"
    wait_for_operator_deployment
    ;;
  install-flowcollector)
    install_netobserv_flowcollector "${FLOWCOLLECTOR_FILE}"
    validate_netobserv_ready
    ;;
  install)
    install_netobserv_operator "${CATALOG_SOURCE}"
    wait_for_cluster_crd "flowcollectors.flows.netobserv.io" "NetObserv FlowCollector" "${NETOBSERV_CRD_WAIT_SECONDS:-720}"
    wait_for_operator_deployment
    install_netobserv_flowcollector "${FLOWCOLLECTOR_FILE}"
    validate_netobserv_ready
    ;;
  delete-flowcollector)
    delete_netobserv_flowcollector
    ;;
  delete-operator)
    delete_netobserv_operator
    ;;
  status)
    status_netobserv
    ;;
  *)
    errormsg "Unknown command [${_CMD}]. See --help."
    exit 1
    ;;
esac
