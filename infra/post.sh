#!/bin/bash
set -o errexit -o nounset -o pipefail

cat post.env
source post.env

# placeholder website
# https://github.com/GoogleCloudPlatform/terraform-dynamic-python-webapp/blob/main/app/placeholder/placeholder-deploy.sh
# docker run -e FIREBASE_URL=${firebase_url} -e SUFFIX=${suffix} -e SUFFIX=${suffix} -v ~/.config/gcloud:/root/.config/gcloud ${placeholder_image}
npm install -g json
curl -Lo ./firebase https://firebase.tools/bin/linux/latest && install -o 0 -g 0 -m 0755 firebase /usr/local/bin/
cd ./app/placeholder
FIREBASE_URL=${firebase_url} SUFFIX=${suffix} SUFFIX=${suffix} PROJECT_ID=${project_id} ./placeholder-deploy.sh
# run jobs

## Client/frontend processing
SETUP_JOB=$(gcloud run jobs list --filter "metadata.name~${client_job_name}$" --format "value(metadata.name)" --region ${region} --project ${project_id})

if [[ -z $SETUP_JOB ]]; then
  echo "Creating ${client_job_name} Cloud Run Job"
  gcloud run jobs create ${client_job_name} --region ${region} --project ${project_id} \
    --image ${client_image} \
    --service-account ${client_sa_email} \
    --set-env-vars PROJECT_ID=${project_id} \
    --set-env-vars SUFFIX=${suffix} \
    --set-env-vars REGION=${region} \
    --set-env-vars SERVICE_NAME=${server_service_name}
else
  echo "Cloud Run Job ${client_job_name} already exists."
fi

 ## Server/API processing
 SETUP_JOB=$(gcloud run jobs list --filter "metadata.name~${setup_job_name}$" --format "value(metadata.name)" --region ${region} --project ${project_id})

if [[ -z $SETUP_JOB ]]; then
  echo "Creating ${setup_job_name} Cloud Run Job"
  gcloud run jobs create ${setup_job_name} --region ${region} --project ${project_id} \
    --command setup \
    --image ${server_image} \
    --service-account ${automation_sa_email} \
    --set-secrets DJANGO_ENV=${django_settings_secret_id}:latest \
    --set-secrets DJANGO_SUPERUSER_PASSWORD=${django_admin_pass_id}:latest \
    --set-cloudsql-instances ${sql_connection_name}
else
  echo "Cloud Run Job ${setup_job_name} already exists."
fi

## Exec jobs
gcloud run jobs execute ${setup_job_name} --wait --region ${region} --project ${project_id}
gcloud run jobs execute ${client_job_name} --wait --region ${region} --project ${project_id}

curl -X PURGE "${firebase_url}/"
curl "${server_url}/api/products/?warmup"