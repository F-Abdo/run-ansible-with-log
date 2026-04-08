#!/bin/bash

# ============================================
# ANSIBLE PLAYBOOK RUNNER WITH ORGANIZED LOGGING
# ============================================

# Configuration
BASE_LOG_DIR="./logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'   #URed="\[\033[4;31m\]"         # Red
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <playbook.yml> [inventory.ini] [options]"
    echo ""
    echo "Examples:"
    echo "  playbook.yml inventory.ini --check"
    echo ""
    exit 1
}

# Function to create playbook-specific directories
setup_playbook_dirs() {
    local playbook_name=$1
    local playbook_dir="${BASE_LOG_DIR}/${playbook_name}"
    
    # Create directory structure
    mkdir -p "${playbook_dir}/runs"
    mkdir -p "${playbook_dir}/reports"
    mkdir -p "${playbook_dir}/backups"
    
    echo "${playbook_dir}"
}

# Function to rotate old logs (keep last 50)
rotate_logs() {
    local playbook_dir=$1
    local runs_dir="${playbook_dir}/runs"
    
    if [ -d "$runs_dir" ]; then
        cd "$runs_dir"
        ls -t *.log 2>/dev/null | tail -n +51 | xargs -r rm
        cd - > /dev/null
    fi
}

# Function to create summary report
create_summary() {
    local log_file=$1
    local report_file=$2
    local playbook=$3
    local inventory=$4
    local exit_code=$5
    
    {
        echo "========================================="
        echo "ANSIBLE PLAYBOOK EXECUTION REPORT"
        echo "========================================="
        echo "Playbook:     $playbook"
        echo "Inventory:    $inventory"
        echo "Start time:   $(date -r "$log_file" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)"
        echo "End time:     $(date)"
        echo "Exit code:    $exit_code"
        echo "Log file:     $log_file"
        echo ""
        echo "========================================="
        echo "EXECUTION SUMMARY"
        echo "========================================="
        grep -E "PLAY RECAP|ok=|failed=|unreachable=|skipped=" "$log_file" | tail -20
        echo ""
        echo "========================================="
        echo "FAILED TASKS (if any)"
        echo "========================================="
        grep -B 2 -A 5 "failed=" "$log_file" | grep -E "TASK|fatal|FAILED" || echo "No failed tasks found"
        echo ""
        echo "========================================="
        echo "SYSTEM INFORMATION (if available)"
        echo "========================================="
        grep -E "SYSTEM INFORMATION|OS INFO|KERNEL|MEMORY|DISK|NETWORK|CPU|Total RAM" "$log_file" | head -30
    } > "$report_file"
}

# Check if playbook is provided
if [ $# -eq 0 ]; then
    usage
fi

PLAYBOOK=$1
INVENTORY=${2:-"inventory.ini"}
EXTRA_ARGS="${@:3}"

# Check if playbook exists
if [ ! -f "$PLAYBOOK" ]; then
    echo -e "${RED}ERROR: Playbook '$PLAYBOOK' not found!${NC}"
    exit 1
fi

# Check if inventory exists
if [ ! -f "$INVENTORY" ]; then
    echo -e "${YELLOW}WARNING: Inventory '$INVENTORY' not found, using default.${NC}"
fi

# Extract playbook name without path and extension
PLAYBOOK_NAME=$(basename "$PLAYBOOK" .yml)
PLAYBOOK_NAME=$(basename "$PLAYBOOK_NAME" .yaml)
PLAYBOOK_NAME=$(echo "$PLAYBOOK_NAME" | sed 's/[^a-zA-Z0-9_-]/_/g')

# Setup playbook-specific directories
PLAYBOOK_LOG_DIR=$(setup_playbook_dirs "$PLAYBOOK_NAME")
RUNS_DIR="${PLAYBOOK_LOG_DIR}/runs"
REPORTS_DIR="${PLAYBOOK_LOG_DIR}/reports"
BACKUPS_DIR="${PLAYBOOK_LOG_DIR}/backups"

# Create log filename with timestamp
LOG_FILE="${RUNS_DIR}/${PLAYBOOK_NAME}-${TIMESTAMP}.log"
REPORT_FILE="${REPORTS_DIR}/report-${TIMESTAMP}.txt"
LATEST_LOG_LINK="${PLAYBOOK_LOG_DIR}/latest.log"
LATEST_REPORT_LINK="${PLAYBOOK_LOG_DIR}/latest-report.txt"

# Backup existing configuration (if any)
if [ -f "$PLAYBOOK" ]; then
    cp "$PLAYBOOK" "${BACKUPS_DIR}/${PLAYBOOK_NAME}-${TIMESTAMP}.yml"
fi

# Clear screen and show header
clear
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}🎯 ANSIBLE PLAYBOOK RUNNER${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${BLUE}📖 Playbook:   ${NC}$PLAYBOOK"
echo -e "${BLUE}📁 Inventory:  ${NC}$INVENTORY"
echo -e "${BLUE}🏷️  Name:       ${NC}$PLAYBOOK_NAME"
echo -e "${BLUE}📂 Log dir:    ${NC}$PLAYBOOK_LOG_DIR"
echo -e "${BLUE}📝 Log file:   ${NC}$LOG_FILE"
echo -e "${BLUE}🕐 Start time: ${NC}$(date)"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Run ansible with logging
echo -e "${YELLOW}▶️  Running Ansible playbook...${NC}"
echo ""

ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --ask-become-pass $EXTRA_ARGS 2>&1 | tee "$LOG_FILE"

# Get exit code
EXIT_CODE=$?

# Create symlinks to latest files
ln -sf "runs/$(basename "$LOG_FILE")" "$LATEST_LOG_LINK"
ln -sf "reports/$(basename "$REPORT_FILE")" "$LATEST_REPORT_LINK"

# Create summary report
create_summary "$LOG_FILE" "$REPORT_FILE" "$PLAYBOOK" "$INVENTORY" "$EXIT_CODE"

# Rotate old logs (keep last 50)
rotate_logs "$PLAYBOOK_LOG_DIR"

# Create master index file
INDEX_FILE="${BASE_LOG_DIR}/INDEX.md"
{
    echo "# Ansible Playbook Logs Index"
    echo ""
    echo "Last updated: $(date)"
    echo ""
    echo "## Playbooks"
    echo ""
    for playbook_dir in ${BASE_LOG_DIR}/*/; do
        if [ -d "$playbook_dir" ]; then
            pb_name=$(basename "$playbook_dir")
            echo "### 📁 ${pb_name}"
            echo "- Latest log: \`${playbook_dir}latest.log\`"
            echo "- Latest report: \`${playbook_dir}latest-report.txt\`"
            echo "- Total runs: $(ls -1 ${playbook_dir}/runs/*.log 2>/dev/null | wc -l)"
            echo ""
        fi
    done
} > "$INDEX_FILE"

# Display results
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ EXECUTION COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${BLUE}🏁 End time:     ${NC}$(date)"
echo -e "${BLUE}📊 Exit code:    ${NC}$EXIT_CODE"
echo -e "${BLUE}📝 Full log:     ${NC}$LOG_FILE"
echo -e "${BLUE}📋 Report:       ${NC}$REPORT_FILE"
echo -e "${BLUE}🔗 Latest log:   ${NC}$LATEST_LOG_LINK"
echo -e "${BLUE}📂 Playbook dir: ${NC}$PLAYBOOK_LOG_DIR"
echo -e "${BLUE}📇 Index file:   ${NC}$INDEX_FILE"
echo -e "${GREEN}=========================================${NC}"

# Show summary if successful
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Playbook completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📊 Quick Summary:${NC}"
    grep -E "PLAY RECAP" "$LOG_FILE" | tail -1
else
    echo -e "${RED}❌ Playbook failed with exit code: $EXIT_CODE${NC}"
    echo ""
    echo -e "${YELLOW}Last 10 lines of log:${NC}"
    echo -e "${RED}-----------------------------------------${NC}"
    tail -10 "$LOG_FILE"
fi

echo ""
echo -e "${YELLOW}💡 Tips:${NC}"
echo -e "   View full log:     cat $LOG_FILE"
echo -e "   View report:       cat $REPORT_FILE"
echo -e "   Watch latest log:  tail -f $LATEST_LOG_LINK"
echo -e "   List all playbooks: ls -la $BASE_LOG_DIR/"
echo ""

exit $EXIT_CODE
