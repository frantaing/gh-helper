#!/usr/bin/env bash

# ---
# Welcome to gh-helper!
# A TUI for doing Github things the website won't let you do.
# ---

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors & styles ---
# Github palette
COLOR_BLUE="#58a6ff"
COLOR_GREEN="#3fb950"
COLOR_RED="#f85149"
COLOR_PURPLE="#a371f7"
COLOR_BORDER="#484f58"

# --- Get the feature modules ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/modules/deployment_cleanup.sh"
source "$SCRIPT_DIR/modules/actions_cache.sh"
source "$SCRIPT_DIR/modules/workflow_cleanup.sh"
source "$SCRIPT_DIR/modules/branch_pruning.sh"

# --- Dependency checker ---
# Checks for required tools and offers to install them if missing.
check_dependencies() {
    local missing_deps=()
    local deps=("gh" "gum" "jq")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        # Use plain echo here — gum may itself be missing at this point
        echo "Warning: Required tools are missing: ${missing_deps[*]}"

        if gum confirm "Would you like to try and install them now?" \
            --prompt.foreground "$COLOR_BLUE" \
            --selected.background "$COLOR_BLUE" \
            --selected.foreground "#FFFFFF"; then
            
            # Detect package manager
            if command -v pacman &> /dev/null; then
                sudo pacman -S "${missing_deps[@]}"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y "${missing_deps[@]}"
            elif command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
            elif command -v brew &> /dev/null; then
                brew install "${missing_deps[@]}"
            else
                gum style --foreground "$COLOR_RED" "Could not detect a supported package manager (apt, dnf, pacman, brew)."
                echo "Please install manually: ${missing_deps[*]}"
                exit 1
            fi
            # Re-check after installation attempt
            check_dependencies
        else
            echo "Please install the missing dependencies to continue."
            exit 1
        fi
    fi
}

# --- Welcome screen ---
display_welcome() {
    local title
    title=$(gum style --foreground "$COLOR_BLUE" "gh-helper")

    local subtitle="A TUI for doing Github things the website won't let you do."
    local version="v1.1.0"

    gum style \
        --border double --border-foreground "$COLOR_BORDER" \
        --align center --width 50 --padding "1 2" \
        "$title" \
        "$subtitle" \
        "$version"

    echo ""
}

# --- Main menu ---
display_main_menu() {
    local header_text
    header_text=$(gum style --bold --foreground "$COLOR_BLUE" "What would you like to do?")

    local choice
    choice=$(gum choose \
        "Deployment Cleanup" \
        "Actions Cache Management" \
        "Bulk Workflow Run Cleanup" \
        "Stale Branch Pruning" \
        "Quit" \
        --height 10 \
        --header "$header_text" \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    case "$choice" in
        "Deployment Cleanup")
            run_deployment_cleanup
            ;;
        "Actions Cache Management")
            run_actions_cache
            ;;
        "Bulk Workflow Run Cleanup")
            run_workflow_cleanup
            ;;
        "Stale Branch Pruning")
            run_branch_pruning
            ;;
        "Quit")
            gum style --foreground "$COLOR_GREEN" "Goodbye!"
            exit 0
            ;;
    esac
}

# --- Main ---
#
#   1. Clears the screen first
#   2. Checks if all required tools are installed
#   3. Checks if the user is authenticated with gh
#       3.5. If not, => `gh auth login`
#   4. Once logged in, show welcome screen
#   5. Loop the main menu until user quits
#
main() {
    clear 
    
    check_dependencies

    if ! gh auth status &>/dev/null; then
        gum style --border normal --border-foreground "$COLOR_RED" --padding "1 2" \
            "You are not authenticated with the GitHub CLI."
        
        if gum confirm "Would you like to run 'gh auth login' now?" \
            --prompt.foreground "$COLOR_BLUE" \
            --selected.background "$COLOR_BLUE" \
            --selected.foreground "#FFFFFF"; then
            gh auth login
        else
            echo "Authentication is required to use gh-helper."
            exit 1
        fi
    fi

    display_welcome

    while true; do
        display_main_menu
    done
}

main
