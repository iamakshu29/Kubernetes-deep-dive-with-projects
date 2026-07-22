#!/bin/bash

read -p "Enter the namespace to switch to: " team_name
kubectl config set-context --current --namespace="$team_name"

echo "Current namespace changed to: $team_name"