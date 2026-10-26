#!/usr/bin/env bash
# Keeps targets/ecs-tasks.json in sync with the RUNNING tasks of one ECS service.
# Usage (leave it running in its own terminal tab during tests):
#   ./update_targets.sh <cluster-name> <service-name>
# Needs: AWS CLI configured for us-west-2 (same credentials you use for Terraform).
set -u
CLUSTER="${1:?cluster name}"
SERVICE="${2:?service name}"
INTERVAL="${3:-10}"
DIR="$(cd "$(dirname "$0")" && pwd)/targets"
OUT="$DIR/ecs-tasks.json"
mkdir -p "$DIR"

while true; do
  TASKS=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
           --desired-status RUNNING --query 'taskArns[]' --output text 2>/dev/null)
  IPS=""
  if [ -n "$TASKS" ] && [ "$TASKS" != "None" ]; then
    ENIS=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks $TASKS \
            --query "tasks[].attachments[].details[?name=='networkInterfaceId'].value[]" \
            --output text 2>/dev/null)
    if [ -n "$ENIS" ] && [ "$ENIS" != "None" ]; then
      IPS=$(aws ec2 describe-network-interfaces --network-interface-ids $ENIS \
             --query 'NetworkInterfaces[].Association.PublicIp' --output text 2>/dev/null)
    fi
  fi

  JSON="["; SEP=""
  for ip in $IPS; do
    [ "$ip" = "None" ] && continue
    JSON="$JSON$SEP{\"targets\":[\"$ip:8080\"],\"labels\":{\"service\":\"$SERVICE\"}}"; SEP=","
  done
  JSON="$JSON]"
  echo "$JSON" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "$(date +%H:%M:%S)  tasks: $(echo $IPS | wc -w | tr -d ' ')  ->  ${IPS:-none}"
  sleep "$INTERVAL"
done
