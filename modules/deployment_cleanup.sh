#!/usr/bin/env bash

# --- MODULE: Deployment Cleanup ---
# Contains all logic for the deployment cleanup feature.

run_deployment_cleanup() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to the Deployment Cleanup Module."

    # --- 1: Get the repo ---
    local REPO_NAME
    while true; do
        REPO_NAME=$(gum input --placeholder "owner/repo" \
            --prompt.bold \
            --prompt "Enter the repository to clean: " \
            --cursor.foreground "$COLOR_BLUE")

        if [ -z "$REPO_NAME" ]; then clear; return; fi

        if gh repo view "$REPO_NAME" &>/dev/null; then
            break
        else
            gum style --foreground "$COLOR_RED" "Error: Repository '$REPO_NAME' not found or you don't have access. Please try again."
        fi
    done

    # --- 2: Select an environment (with loop for retry) ---
    while true; do
        local get_envs_cmd="gh api 'repos/$REPO_NAME/environments' --jq '.environments.[].name' 2>/dev/null || true"
        
        local ENV_NAMES
        ENV_NAMES=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Fetching environments for $REPO_NAME..." -- bash -c "$get_envs_cmd")

        if [ -z "$ENV_NAMES" ]; then
            gum style --foreground "$COLOR_RED" "No environments found for '$REPO_NAME'."
            sleep 3
            clear
            return
        fi

        local ENV_NAME
        ENV_NAME=$(echo "$ENV_NAMES" | gum choose \
            --header "Select an environment to clean" \
            --header.bold \
            --header.foreground "" \
            --cursor.foreground "$COLOR_BLUE" \
            --selected.foreground "$COLOR_BLUE")

        if [ -z "$ENV_NAME" ]; then clear; return; fi

        # --- 3: Get deployments ---
        local get_deployments_cmd="gh api 'repos/$REPO_NAME/deployments?per_page=100' --paginate --jq '.[] | select(.environment == \"$ENV_NAME\") | {id: .id, env: .environment, creator: .creator.login, created: .created_at}' 2>/dev/null || true"

        local DEPLOYMENTS_JSON
        DEPLOYMENTS_JSON=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Fetching deployments in '$ENV_NAME'..." -- bash -c "$get_deployments_cmd")
        
        # Check if deployments exist
        if [ -z "$DEPLOYMENTS_JSON" ] || [ "$DEPLOYMENTS_JSON" = "null" ]; then
            echo
            gum style --padding "1 2" --border normal --border-foreground "#f8e45c" \
                "No deployments found in the '$ENV_NAME' environment." \
                "Please select a different environment."
            echo
            
            if ! gum confirm "Would you like to choose a different environment?" \
                --prompt.bold \
                --prompt.foreground "" \
                --selected.background "$COLOR_BLUE" \
                --selected.foreground "#FFFFFF"; then
                clear
                return
            fi
            
            clear
            # Loop continues, allowing user to select another environment
            continue
        fi
        
        # Extract IDs for counting and deletion
        local DEPLOYMENT_IDS
        DEPLOYMENT_IDS=$(echo "$DEPLOYMENTS_JSON" | jq -r '.id' | grep -v '^$')
        
        local DEPLOYMENT_COUNT
        DEPLOYMENT_COUNT=$(echo "$DEPLOYMENT_IDS" | wc -l | xargs)

        # If DEPLOYMENT_IDS is empty or just whitespace, treat as no deployments
        if [ -z "$(echo "$DEPLOYMENT_IDS" | xargs)" ]; then
            echo
            gum style --padding "1 2" --border normal --border-foreground "#f8e45c" \
                "No deployments found in the '$ENV_NAME' environment." \
                "Please select a different environment."
            echo
            
            if ! gum confirm "Would you like to choose a different environment?" \
                --prompt.bold \
                --prompt.foreground "" \
                --selected.background "$COLOR_BLUE" \
                --selected.foreground "#FFFFFF"; then
                clear
                return
            fi
            
            clear
            # Loop continues, allowing user to select another environment
            continue
        fi
        
        # If we have deployments, break out of the loop
        break
    done

    # --- 3.5: Show deployments ---
    echo
    gum style --bold --foreground "$COLOR_GREEN" "Found $DEPLOYMENT_COUNT deployment(s) in '$ENV_NAME':"
    
    # Warn if pagination limits is reached
    if [ "$DEPLOYMENT_COUNT" -ge 100 ]; then
        echo
        gum style --foreground "#f8e45c" "⚠ Note: There are 100+ deployments. Make sure all are loaded."
    fi
    
    echo
    
    # Display in a nice table format
    echo "$DEPLOYMENTS_JSON" | jq -r '"  ID: \(.id) | Creator: \(.creator) | Created: \(.created)"'
    echo

    # --- 4: Show action menu ---
    local action
    action=$(gum choose \
        "Delete ALL deployments" \
        "Delete specific deployments (select)" \
        "Cancel" \
        --header "What would you like to do?" \
        --header.bold \
        --header.foreground "" \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")
    
    if [ "$action" = "Cancel" ]; then
        clear
        return
    fi
    
    # --- 5: Handle selection (if selective deletion) ---
    local SELECTED_IDS="$DEPLOYMENT_IDS"
    local SELECTED_COUNT="$DEPLOYMENT_COUNT"
    
    if [ "$action" = "Delete specific deployments (select)" ]; then
        echo
        gum style --bold "Select deployments to delete (use Space to select, Enter to confirm):"
        echo
        
        # Create formatted list for selection
        local deployment_options
        deployment_options=$(echo "$DEPLOYMENTS_JSON" | jq -r '"[\(.id)] \(.creator) - \(.created)"')
        
        if [ -z "$deployment_options" ]; then
            gum style --foreground "$COLOR_RED" "Error creating selection list."
            sleep 2
            clear
            return
        fi
        
        # Let user select multiple deployments
        local selected_deployments
        selected_deployments=$(echo "$deployment_options" | gum choose --no-limit \
            --cursor.foreground "$COLOR_BLUE" \
            --selected.foreground "$COLOR_BLUE")
        
        if [ -z "$selected_deployments" ]; then
            gum style --foreground "$COLOR_BLUE" "No deployments selected."
            sleep 2
            clear
            return
        fi
        
        # Get IDs from selected items
        SELECTED_IDS=$(echo "$selected_deployments" | sed 's/^\[\([0-9]*\)\].*/\1/')
        SELECTED_COUNT=$(echo "$SELECTED_IDS" | grep -c . || echo "0")
        
        echo
        gum style --foreground "$COLOR_GREEN" "Selected $SELECTED_COUNT deployment(s) for deletion."
        sleep 1
    fi

    # --- 6: CONFIRM DELETION ---
    echo
    if ! gum confirm "You are about to PERMANENTLY delete ${SELECTED_COUNT} deployment(s) from the \"${ENV_NAME}\" environment. Proceed?" \
        --prompt.bold \
        --prompt.foreground "" \
        --selected.background "$COLOR_BLUE" \
        --selected.foreground "#FFFFFF"; then
        clear
        return
    fi

    # --- 7: Deletion loop ---
    clear
    gum style --bold --foreground "$COLOR_BLUE" -- "--- Starting Deletion Process ---"
    echo

    # !!! Temporarily disable 'set -e' for this section
    # Or else the program will just exit out!
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
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Processing deployment $i of $SELECTED_COUNT (ID: $id)..."

        # Try to delete directly first
        gh api --method DELETE "repos/$REPO_NAME/deployments/$id" --silent 2>/dev/null
        local delete_result=$?
        
        if [ $delete_result -eq 0 ]; then
            echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
            ((deleted_count++))
        else
            # If fails, mark as inactive first
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
    done <<< "$SELECTED_IDS"
    
    # Re-enable 'set -e'
    set -e

    echo
    local line1="✨ Process Complete! ✨"
    local line2
    line2=$(gum style --foreground "$COLOR_GREEN" "Deleted ${deleted_count} of ${SELECTED_COUNT} deployments from the '${ENV_NAME}' environment.")
    
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "$line1" \
        "$line2"

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}