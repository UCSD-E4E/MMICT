#!/bin/bash
set -euo pipefail

#define resource to exclude
EXCLUDE_PATTERN="^aws_ecr_repository\.ecr_repo\["
#exclude ecr repo + ecr lifecycle policy
#EXCLUDE_PATTERN="^aws_ecr_repository\.ecr_repo\[|^aws_ecr_lifecycle_policy\.ecr_lifecycle_policy\["

ALL_RESOURCES=$(terraform state list)

RESOURCES_TO_DESTROY=$(grep -Ev "${EXCLUDE_PATTERN}" <<<"$ALL_RESOURCES")

#error checking
if [ -z "$RESOURCES_TO_DESTROY" ]; then
  echo "No resources to destroy."
  exit 0
fi

#construct destroy command
DESTROY_CMD=(terraform destroy -var-file=secrets.tfvars)
while read -r RESOURCE; do
  DESTROY_CMD+=( -target="$RESOURCE" )
done <<<"$RESOURCES_TO_DESTROY"

#print and confirm command
echo "About to run:"
printf "  %s\n" "${DESTROY_CMD[@]}"
read -p "Proceed with destruction? (yes/no): " CONFIRM

if [[ "$CONFIRM" == "yes" ]]; then
  "${DESTROY_CMD[@]}"
else
  echo "Destruction cancelled."
fi
