#!/usr/bin/env bash

# --- MODULE: Deployment Cleanup ---
# Contains all logic for the deployment cleanup feature.

run_deployment_cleanup() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to the Deployment Cleanup Module."

    # --- 1: Get/validate repository ---
    local REPO_NAME
    while true; do
        REPO_NAME=$(gum input --placeholder "owner/repo" --prompt "Enter the repository to clean: ")

        if [ -z "$REPO_NAME" ]; then clear; return; fi

        if gh repo view "$REPO_NAME" &>/dev/null; then
            break
        else
            gum style --foreground "$COLOR_RED" "Error: Repository '$REPO_NAME' not found or you don't have access. Please try again."
        fi
    done

    # --- 2: Choose environment ---
    local get_envs_cmd="gh api 'repos/$REPO_NAME/environments' --jq '.environments.[].name' 2>/dev/null || true"
    
    local ENV_NAMES
    ENV_NAMES=$(gum spin --spinner dot --title "Fetching environments for $REPO_NAME..." -- bash -c "$get_envs_cmd")

    if [ -z "$ENV_NAMES" ]; then
        gum style --foreground "$COLOR_RED" "No environments with deployment history found for '$REPO_NAME'."
        sleep 3
        clear
        return
    fi

    local ENV_NAME
    ENV_NAME=$(echo "$ENV_NAMES" | gum choose --header "Select an environment to clean")

    if [ -z "$ENV_NAME" ]; then clear; return; fi

    # --- 3: Get deployments from env ---
    local get_ids_cmd="gh api 'repos/$REPO_NAME/deployments' --paginate --jq '.[] | select(.environment == \"$ENV_NAME\") | .id' 2>/dev/null || true"

    local DEPLOYMENT_IDS
    DEPLOYMENT_IDS=$(gum spin --spinner dot --title "Counting deployments in '$ENV_NAME'..." -- bash -c "$get_ids_cmd")
    
    # Debug: Show what was fetched
    if [ -n "$DEPLOYMENT_IDS" ]; then
        echo "DEBUG: Found deployment IDs:"
        echo "$DEPLOYMENT_IDS"
        echo "---"
    else
        echo "DEBUG: DEPLOYMENT_IDS is empty!"
    fi
    
    local DEPLOYMENT_COUNT
    DEPLOYMENT_COUNT=$(echo "$DEPLOYMENT_IDS" | grep -c . || echo "0")

    if [ "$DEPLOYMENT_COUNT" -eq 0 ]; then
        gum style --foreground "$COLOR_GREEN" "The '$ENV_NAME' environment has no deployments to clean."
        sleep 3
        clear
        return
    fi

    # --- 4: Show action menu ---
    echo
    gum style --bold "What would you like to do?"
    
    local action
    action=$(gum choose \
        "Delete ALL deployments" \
        "Cancel" \
        --cursor.foreground "$COLOR_BLUE")
    
    if [ "$action" = "Cancel" ]; then
        clear
        return
    fi

    # --- 5: CONFIRM DELETION? ---
    echo
    if ! gum confirm "You are about to PERMANENTLY delete all ${DEPLOYMENT_COUNT} deployments from the \"${ENV_NAME}\" environment. Proceed?"; then
        clear
        return
    fi

    # --- 6: Deletion loop ---
    clear
    gum style --bold --foreground "$COLOR_PURPLE" -- "--- Starting Deletion Process ---"
    echo
    
    # Debug: Check what what is being deleted
    echo "DEBUG: About to process these IDs:"
    echo "$DEPLOYMENT_IDS"
    echo "DEBUG: Count is: $DEPLOYMENT_COUNT"
    echo "---"

    # !!! Temporarily disable 'set -e' for this section
    set +e
    
    local i=0
    local deleted_count=0
    
    while IFS= read -r id; do
        # Skip empty lines
        [ -z "$id" ] && continue
        
        # Skip if id is just whitespace
        id=$(echo "$id" | xargs)
        [ -z "$id" ] && continue

        ((i++))
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Processing deployment $i of $DEPLOYMENT_COUNT (ID: $id)..."

        # Try to delete directly first
        gh api --method DELETE "repos/$REPO_NAME/deployments/$id" --silent 2>/dev/null
        local delete_result=$?
        
        if [ $delete_result -eq 0 ]; then
            echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
            ((deleted_count++))
        else
            # If it fails, mark as inactive first
            echo "  $(gum style --foreground "#f8e45c" "…") Active deployment. Marking as 'inactive' first..."
            gh api --method POST "repos/$REPO_NAME/deployments/$id/statuses" \
                -f state='inactive' \
                -f description='Decommissioning for cleanup' \
                --silent 2>/dev/null
            
            # Try deleting again
            gh api --method DELETE "repos/$REPO_NAME/deployments/$id" --silent 2>/dev/null
            delete_result=$?
            
            if [ $delete_result -eq 0 ]; then
                 echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
                 ((deleted_count++))
            else
                 echo "  $(gum style --foreground "$COLOR_RED" "✖") FAILED to delete deployment ID: $id."
            fi
        fi
    done <<< "$DEPLOYMENT_IDS"
    
    # Re-enable 'set -e'
    set -e
    
    echo "DEBUG: Loop finished. Deleted: $deleted_count"

    echo
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "✨ Process Complete! ✨" \
        "Deleted ${deleted_count} of ${DEPLOYMENT_COUNT} deployments from the '${ENV_NAME}' environment."

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}