#!/usr/bin/env bash

# This script listens to Nomad allocation events and sends Slack notifications for failed cron jobs and service jobs.
# Define NOMAD_ADDR and SLACK_WEBHOOK_URL environment variables before running the script.

curl -s -N "${NOMAD_ADDR}/v1/event/stream?topic=Allocation" \
| jq --unbuffered -c '
    select(.Events != null)
    | .Events[]
    | select(.Type=="AllocationUpdated")
    | select(.Payload.Allocation.ClientStatus=="failed")
    | {
        job: .Payload.Allocation.JobID,
        job_url: ("'"${NOMAD_ADDR}"'/ui/jobs/" + (.Payload.Allocation.JobID | gsub("/"; "%2F"))),
        alloc: .Payload.Allocation.ID,
        node: .Payload.Allocation.NodeName,
        failed_tasks: (
            .Payload.Allocation.TaskStates
            | to_entries[]
            | select(.value.Failed==true)
            | {
                task: .key,
                started: .value.StartedAt,
                finished: .value.FinishedAt,
                messages: (.value.Events | map(.DisplayMessage) | join(" | "))
              }
        )
      } ' \
| while IFS= read -r line; do
    # Always log full JSON locally
    echo "⚠️ Allocation failed: $line"

    job=$(echo "$line" | jq -r .job)

    # Only notify Slack if job starts with "cron-" or "service-"
    # but not "*slack-alerts"
    if [[ ( "$job" == cron-* || "$job" == service-* ) && "$job" != *slack-alerts ]]; then
        echo "📝 Firing slack notification for cron job: $job"
                # Convert times to America/Los_Angeles
        started_iso=$(echo "$line" | jq -r '.failed_tasks.started')
        finished_iso=$(echo "$line" | jq -r '.failed_tasks.finished')

        started_local=$(date -d "$started_iso" "+%Y-%m-%d %H:%M:%S")
        finished_local=$(date -d "$finished_iso" "+%Y-%m-%d %H:%M:%S")

        # Build Slack payload
        payload=$(echo "$line" | jq -c --arg started "$started_local" --arg finished "$finished_local" '
          {
            text: (
              "⚠️ Nomad Cron/Service Fails: *\(.job)*\n📌 Alloc: \(.alloc)\n📝 Task: \(.failed_tasks.task)\n🖥️ Node: \(.node)\n⏳ \($started) --> \($finished)\n💬 \(.failed_tasks.messages)\n🔗 \(.job_url)"
            )
          }
        ')

        # Send to Slack
        curl -s -X POST -H 'Content-type: application/json' \
             --data "$payload" \
             "$SLACK_WEBHOOK_URL"
    fi
done
