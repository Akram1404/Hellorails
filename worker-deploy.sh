#!/bin/bash

set -euo pipefail

IMAGE="${WORKER_REPOSITORY_URI}:${IMAGE_TAG}"

echo "Worker Image: ${IMAGE}"

TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "${TASK_DEFINITION}" \
  --region "${AWS_REGION}")

NEW_CONTAINER_DEFINITIONS=$(echo "${TASK_DEF}" | jq \
  --arg IMAGE "${IMAGE}" \
  --arg CONTAINER_NAME "${CONTAINER_NAME}" \
  '
  .taskDefinition.containerDefinitions
  | map(
      if .name == $CONTAINER_NAME then
        .image = $IMAGE
      else
        .
      end
    )
  ')

TASK_VERSION=$(aws ecs register-task-definition \
  --family "${TASK_DEFINITION}" \
  --container-definitions "${NEW_CONTAINER_DEFINITIONS}" \
  --execution-role-arn "${TASK_EXECUTION_ROLE_ARN}" \
  --task-role-arn "${TASK_ROLE_ARN}" \
  --network-mode bridge \
  --requires-compatibilities EC2 \
  --tags \
    key=commit,value="${CODEBUILD_RESOLVED_SOURCE_VERSION}" \
    key=branch_name,value="${CODEBUILD_SOURCE_VERSION}" \
  | jq -r '.taskDefinition.revision')

echo "Registered ECS Task Definition Revision: ${TASK_VERSION}"

if [ -n "${TASK_VERSION}" ]; then
    aws ecs update-service \
      --cluster "${CLUSTER_NAME}" \
      --service "${SERVICE_NAME}" \
      --task-definition "${TASK_DEFINITION}:${TASK_VERSION}" \
      --force-new-deployment

    echo "Worker deployment completed."
else
    echo "Failed to register task definition."
    exit 1
fi
