#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Safety feature: exit script if error is returned, or if variables not set.
# Exit if a pipeline results in an error.
set -ue
set -o pipefail

## Automatic EBS Volume Snapshot Creation & Clean-Up Script
# This script is created for Software Houses by Web That Matters to Automatically create and manage EC2 snapshots from Multiple Accounts.
# The Basic functionality of the script is written by Casey Labs Inc. (https://www.caseylabs.com)
# Additonal credits: Log function by Alan Franzoni; Pre-req check by Colin Johnson
#
# PURPOSE: This Bash script can be used to take automatic snapshots of your Linux EC2 instance. Script process:
# - Determine the instance ID of the EC2 server on which the script runs
# - Gather a list of all volume IDs attached to that instance
# - Take a snapshot of each attached volume
# - Optionally copy to AWS manager account
# - The script will then delete all associated snapshots taken by the script that are older than 7 days
#
# DISCLAIMER: This script deletes snapshots (though only the ones that it creates). 
# Make sure that you understand how the script works. No responsibility accepted in event of accidental data loss.
#

# Get Instance Details
read snapshot_name
read instance_id
read region
read aws_profile
read retention_days

# Set Logging Options
logfile=$(dirname "$0")"/logs/${snapshot_name// /_}-snapshot.log"
logfile_max_lines="5000"

# How many days do you wish to retain backups for? Default: 7 days
retention_date_in_seconds=$(date +%s --date "$retention_days days ago")

## Function Declarations ##

# Function: Log an event.
log() {
  echo "[$(date +"%Y-%m-%d"+"%T")]: $*"
}
# Function: Setup logfile and redirect stdout/stderr.
log_setup() {
  # Check if logfile exists and is writable.
  ( [ -e "$logfile" ] || touch "$logfile" ) && [ ! -w "$logfile" ] && echo "ERROR: Cannot write to $logfile. Check permissions or sudo access." && exit 1

  tmplog=$(tail -n $logfile_max_lines $logfile 2>/dev/null) && echo "${tmplog}" > $logfile
  exec > >(tee -a $logfile)
  exec 2>&1
  log '--------------------------------------------------------------------------------------------------------'
  log '|'
  log '|'
  log '-------------------------------- AUTOMATED Snapshot Backup has started ----------- Time in UTC ---------'
}

# Function: Manager AWS account configuration to manage all your snapshots from one account (manager.conf)
manager_account_configuration() {
  if ! . $(dirname "$0")/manager.conf &> /dev/null; then
    log 'Manager Account not found.'
    default_aws_profile=$aws_profile
  else
    log 'Manager Account found.'
  fi
}

# Function: Confirm that the AWS CLI and related tools are installed.
prerequisite_check() {
  for prerequisite in aws wget; do
    hash $prerequisite &> /dev/null
    if [[ $? == 1 ]]; then
      echo "In order to use this script, the executable \"$prerequisite\" must be installed." 1>&2; exit 70
    fi
  done
}

# Function: Snapshot all volumes attached to this instance.
snapshot_volumes() {
  for volume_id in $volume_list; do
    log "Volume ID is $volume_id"

    # Get the attched device name to add to the description so we can easily tell which volume this is.
    device_name=$(aws --profile $aws_profile ec2 describe-volumes --region $region --output=text --volume-ids $volume_id --query 'Volumes[0].{Devices:Attachments[0].Device}')

    # Take a snapshot of the current volume, and capture the resulting snapshot ID
    snapshot_description="automated-backup-$(hostname)-$device_name-$(date +%Y-%m-%d)"
    snapshot_id=$(aws --profile $aws_profile ec2 create-snapshot --region $region --output=text --description $snapshot_description --volume-id $volume_id --query SnapshotId)
    log "New snapshot is $snapshot_id"

    # Add a "CreatedBy:AutomatedBackup" tag to the resulting snapshot.
    # Why? Because we only want to purge snapshots taken by the script later, and not delete snapshots manually taken.
    aws --profile $aws_profile ec2 create-tags --region $region --resource $snapshot_id --tags Key=Name,Value=$snapshot_name Key=BackuperHostname,Value=$(hostname) Key=RootDevice,Value=$device_name Key=CreatedBy,Value=AutomatedBackup Key=RetentionDays,Value=$retention_days
    # if manager.conf file exists will give permissions to manager account id and will re-add all snapshot tags to this account-snapshot as well
    
    if [ "$aws_profile" != "$default_aws_profile" ]; then
      log "Copying Snapshot to Manager Account."
      aws --profile $aws_profile ec2 modify-snapshot-attribute --region $region --snapshot-id $snapshot_id --attribute createVolumePermission --operation-type add --user-ids $default_aws_user_id
      aws --profile $default_aws_profile ec2 create-tags --region $region --resource $snapshot_id --tags Key=Name,Value=$snapshot_name Key=BackuperHostname,Value=$(hostname) Key=RootDevice,Value=$device_name Key=CreatedBy,Value=AutomatedBackup Key=RetentionDays,Value=$retention_days Key=AwsCliBackuperProfile,Value=$aws_profile 
    fi
  done
}

# Function: Cleanup all snapshots associated with this instance that are older than $retention_days
cleanup_snapshots() {
  for volume_id in $volume_list; do
    snapshot_list=$(aws --profile $aws_profile ec2 describe-snapshots --region $region --output=text --filters "Name=volume-id,Values=$volume_id" "Name=tag:CreatedBy,Values=AutomatedBackup" --query Snapshots[].SnapshotId)
    for snapshot in $snapshot_list; do
      log "Checking $snapshot..."
      # Check age of snapshot
      snapshot_date=$(aws --profile $aws_profile ec2 describe-snapshots --region $region --output=text --snapshot-ids $snapshot --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
      snapshot_date_in_seconds=$(date "--date=$snapshot_date" +%s)
      snapshot_description=$(aws --profile $aws_profile ec2 describe-snapshots --snapshot-id $snapshot --region $region --query Snapshots[].Description)

      if (( $snapshot_date_in_seconds <= $retention_date_in_seconds )); then
        log "DELETING snapshot $snapshot. Description: $snapshot_description ..."
        aws --profile $aws_profile ec2 delete-snapshot --region $region --snapshot-id $snapshot
      else
        log "Not deleting snapshot $snapshot. Description: $snapshot_description ..."
      fi
    done
  done
}

## SCRIPT COMMANDS ##
log_setup
manager_account_configuration
prerequisite_check

# Grab all volume IDs attached to this instance
volume_list=$(aws --profile $aws_profile ec2 describe-volumes --region $region --filters Name=attachment.instance-id,Values=$instance_id --query Volumes[].VolumeId --output text)

snapshot_volumes
cleanup_snapshots
