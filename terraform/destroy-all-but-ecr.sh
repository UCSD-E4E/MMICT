#!/bin/bash

#define resource to exclude
EXCLUDE_RESOURCE="aws_ecr_repository.mmict-ecr-repo"

ALL_RESOURCES=$(terraform state list)

RESOURCES_TO_DESTROY=$(echo "$ALL_RESOURCES" | grep -v "$EXCLUDE_RESOURCE")

#error checking
if [ -z "$RESOURCES_TO_DESTROY" ]; then
  echo "No resources to destroy."
  exit 0
fi

#construct destroy command
DESTROY_CMD="terraform destroy -var-file=secrets.tfvars"
for RESOURCE in $RESOURCES_TO_DESTROY; do
  DESTROY_CMD+=" -target=$RESOURCE"
done

#print and confirm command
echo "Executing: $DESTROY_CMD"
read -p "Proceed with destruction? (yes/no): " CONFIRM

if [[ "$CONFIRM" == "yes" ]]; then
  eval "$DESTROY_CMD"
else
  echo "Destruction cancelled."
fi
