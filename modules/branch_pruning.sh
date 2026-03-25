#!/usr/bin/env bash

# --- MODULE: Stale Branch Pruning ---
# Finds and deletes branches that haven't been updated recently across one or multiple repos.

run_branch_pruning() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to Stale Branch Pruning."

    # --- 1: Select mode ---
    local MODE
    MODE=$(gum choose \
        "Single Repository" \
        "Multiple Repositories" \
        "Cancel" \
        --header "Prune branches in:" \
        --header.bold \
        --header.foreground "" \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    if [ "$MODE" = "Cancel" ] || [ -z "$MODE" ]; then clear; return; fi

    local SELECTED_REPOS=""

    # --- 2: Get repo(s) ---
    if [ "$MODE" = "Single Repository" ]; then
        while true; do
            local REPO_NAME
            REPO_NAME=$(gum input --placeholder "owner/repo" \
                --prompt.bold \
                --prompt "Enter the repository: " \
                --cursor.foreground "$COLOR_BLUE")

            if [ -z "$REPO_NAME" ]; then clear; return; fi

            if gh repo view "$REPO_NAME" &>/dev/null; then
                SELECTED_REPOS="$REPO_NAME"
                break
            else
                gum style --foreground "$COLOR_RED" "Error: Repository '$REPO_NAME' not found or you don't have access."
            fi
        done
    else
        # Multiple repositories flow
        local ACCOUNT_TYPE
        ACCOUNT_TYPE=$(gum choose \
            "Personal Account" \
            "Organization" \
            --header "Fetch repositories from:" \
            --header.bold \
            --header.foreground "" \
            --cursor.foreground "$COLOR_BLUE" \
            --selected.foreground "$COLOR_BLUE")
        
        if [ -z "$ACCOUNT_TYPE" ]; then clear; return; fi

        local REPOS_JSON
        if [ "$ACCOUNT_TYPE" = "Organization" ]; then
            local ORG_NAME
            ORG_NAME=$(gum input --placeholder "organization-name" \
                --prompt.bold \
                --prompt "Enter Organization name: " \
                --cursor.foreground "$COLOR_BLUE")
            
            if [ -z "$ORG_NAME" ]; then clear; return; fi
            
            REPOS_JSON=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Fetching org repositories..." \
                -- gh api "orgs/$ORG_NAME/repos?per_page=100" --paginate --jq '.[].full_name' 2>/dev/null || true)
        else
            REPOS_JSON=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Fetching personal repositories..." \
                -- gh api "user/repos?per_page=100" --paginate --jq '.[].full_name' 2>/dev/null || true)
        fi

        if [ -z "$REPOS_JSON" ]; then
            gum style --foreground "$COLOR_RED" "No repositories found or access denied."
            sleep 2
            clear; return
        fi

        echo
        gum style --bold "Select repositories to scan:"
        gum style --foreground "$COLOR_BORDER" "(Space to select, 'a' to select all, Enter to confirm)"
        echo
        
        SELECTED_REPOS=$(echo "$REPOS_JSON" | gum choose --no-limit --height 15 \
            --cursor.foreground "$COLOR_BLUE" \
            --selected.foreground "$COLOR_BLUE")
        
        if [ -z "$SELECTED_REPOS" ]; then
            gum style --foreground "$COLOR_BLUE" "No repositories selected."
            sleep 2
            clear; return
        fi
    fi

    # --- 3: Ask for staleness threshold ---
    local THRESHOLD_DAYS
    while true; do
        echo
        THRESHOLD_DAYS=$(gum input --placeholder "90" \
            --value "90" \
            --prompt.bold \
            --prompt "Enter staleness threshold in days: " \
            --cursor.foreground "$COLOR_BLUE")

        if [ -z "$THRESHOLD_DAYS" ]; then clear; return; fi

        if [[ "$THRESHOLD_DAYS" =~ ^[0-9]+$ ]] && [ "$THRESHOLD_DAYS" -gt 0 ]; then
            break
        else
            gum style --foreground "$COLOR_RED" "Please enter a valid positive integer."
        fi
    done

    local current_epoch=$(date +%s)
    local threshold_seconds=$((THRESHOLD_DAYS * 86400))
    local cutoff_epoch=$((current_epoch - threshold_seconds))

    # --- 4: Fetch data & calculate staleness ---
    echo
    gum style --foreground "$COLOR_BORDER" "Scanning selected repositories... (This may take a while for many repos)"
    
    local fetch_script=$(cat <<EOF
    while IFS= read -r repo; do
        [ -z "\$repo" ] && continue
        
        DEFAULT_BRANCH=\$(gh repo view "\$repo" --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)
        BRANCHES=\$(gh api "repos/\$repo/branches?per_page=100" --paginate --jq '.[].name' 2>/dev/null)
        [ -z "\$BRANCHES" ] && continue

        for branch in \$BRANCHES; do
            if [ "\$branch" = "\$DEFAULT_BRANCH" ]; then continue; fi

            commit_date=\$(gh api "repos/\$repo/commits/\$branch" --jq '.commit.committer.date' 2>/dev/null)
            [ -z "\$commit_date" ] && continue

            commit_epoch=\$(date -d "\$commit_date" +%s 2>/dev/null || echo 0)

            if [ "\$commit_epoch" -lt "$cutoff_epoch" ] && [ "\$commit_epoch" -gt 0 ]; then
                diff_seconds=\$(( $current_epoch - commit_epoch ))
                days_ago=\$(( diff_seconds / 86400 ))
                # Output format: repo|branch_name|days_ago|actual_date
                echo "\$repo|\$branch|\$days_ago|\$commit_date"
            fi
        done
    done <<< "$SELECTED_REPOS"
EOF
    )

    local STALE_BRANCHES
    STALE_BRANCHES=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Analyzing branch ages across repos..." -- bash -c "$fetch_script")

    if [ -z "$STALE_BRANCHES" ]; then
        gum style --foreground "$COLOR_GREEN" "Nice! No branches older than $THRESHOLD_DAYS days found in the selected repos."
        sleep 3
        clear
        return
    fi

    # --- 5: Present selection lists ---
    # Format:[owner/repo:branch_name] last updated 95 days ago
    local formatted_list
    formatted_list=$(echo "$STALE_BRANCHES" | awk -F'|' '{ printf "[%s:%s] last updated %s days ago\n", $1, $2, $3 }')

    echo
    gum style --bold "Select stale branches to delete:"
    gum style --foreground "$COLOR_BORDER" "(Space to select, 'a' to select all, Enter to confirm)"
    echo

    local selected_lines
    selected_lines=$(echo "$formatted_list" | gum choose --no-limit --height 15 \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    if [ -z "$selected_lines" ]; then
        gum style --foreground "$COLOR_BLUE" "No branches selected."
        sleep 2
        clear
        return
    fi

    # Extract [repo:branch] string. Output lines look like: owner/repo:branch_name
    local TARGETS
    TARGETS=$(echo "$selected_lines" | sed 's/^\[\(.*\)\] last updated.*/\1/')
    local COUNT
    COUNT=$(echo "$TARGETS" | grep -c . || echo "0")

    # --- 6: Confirm deletion ---
    echo
    if ! gum confirm "You are about to PERMANENTLY delete $COUNT branch(es). Proceed?" \
        --prompt.bold \
        --prompt.foreground "" \
        --selected.background "$COLOR_BLUE" \
        --selected.foreground "#FFFFFF"; then
        clear
        return
    fi

    # --- 7: Deletion loop ---
    clear
    gum style --bold --foreground "$COLOR_BLUE" -- "--- Deleting Branches ---"
    echo

    set +e
    local i=0
    local deleted_count=0

    while IFS= read -r target; do
        [ -z "$target" ] && continue
        
        # Split owner/repo:branch_name into separate variables using parameter expansion
        local repo_name="${target%:*}"   # Everything before the last colon
        local branch_name="${target##*:}" # Everything after the last colon

        ((i++))
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Deleting branch $i of $COUNT ($repo_name:$branch_name)..."
        
        if gh api --method DELETE "repos/$repo_name/git/refs/heads/$branch_name" --silent 2>/dev/null; then
            echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
            ((deleted_count++))
        else
            echo "  $(gum style --foreground "$COLOR_RED" "✖") Failed to delete branch."
        fi
    done <<< "$TARGETS"
    set -e

    # --- 8: SUCCESS! ---
    echo
    local line1="✨ Process Complete! ✨"
    local line2
    line2=$(gum style --foreground "$COLOR_GREEN" "Deleted $deleted_count of $COUNT stale branches.")

    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "$line1" "$line2"

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}