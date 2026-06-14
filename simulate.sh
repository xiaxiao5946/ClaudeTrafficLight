#!/bin/bash
# Simulate a Claude Code session lifecycle for testing ClaudeTrafficLight
# Usage: ./simulate.sh
# Requires ClaudeTrafficLight.app to be running

set -e
cd "$(dirname "$0")"

echo "=== ClaudeTrafficLight Session Simulator ==="
echo "Make sure ClaudeTrafficLight is running first: open build/ClaudeTrafficLight.app"
echo ""

# Create a dummy process for a real PID
sleep 999 &
FAKE_PID=$!
SID="sim-$(date +%s)"
NOW=$(python3 -c "import time; print(int(time.time()*1000))")
PROJ="-Users-kika-xxinfos-AI-project-ClaudeTrafficLight"
mkdir -p "$HOME/.claude/projects/$PROJ"

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    kill $FAKE_PID 2>/dev/null
    rm -f "$HOME/.claude/sessions/$FAKE_PID.json"
    rm -f "$HOME/.claude/projects/$PROJ/$SID.jsonl"
    echo "Simulation session removed"
}
trap cleanup EXIT

# Step 1: Create session (busy/executing)
cat > "$HOME/.claude/sessions/$FAKE_PID.json" << JSON
{"pid":$FAKE_PID,"sessionId":"$SID","cwd":"/Users/kika/xxinfos/AI/project/ClaudeTrafficLight","startedAt":$NOW,"version":"2.1.0","kind":"interactive","entrypoint":"sdk-ts","status":"busy"}
JSON

TS=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"帮我分析项目结构"}]},"timestamp":"'$TS'","sessionId":"'$SID'"}' > "$HOME/.claude/projects/$PROJ/$SID.jsonl"

echo "Step 1: Session started (busy/executing)"
echo "  → You should see 🟡 flash + notification '开始执行'"
sleep 6

# Step 2: Blocked (waiting for confirmation)
echo ""
echo "Step 2: Session blocked (waiting confirmation)"
TS2=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
cat >> "$HOME/.claude/projects/$PROJ/$SID.jsonl" << JSONL
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}],"stop_reason":"tool_use"},"timestamp":"$TS2","sessionId":"$SID"}
{"type":"system","subtype":"permission_request","timestamp":"$TS2","sessionId":"$SID"}
JSONL
python3 -c "import json; d=json.load(open('$HOME/.claude/sessions/$FAKE_PID.json')); d['status']='blocked'; json.dump(d,open('$HOME/.claude/sessions/$FAKE_PID.json','w'))"

echo "  → You should see 🟡 double-flash + notification '等待确认'"
echo "  → Window should auto-expand if collapsed"
sleep 6

# Step 3: Complete
echo ""
echo "Step 3: Session complete (idle)"
TS3=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
cat >> "$HOME/.claude/projects/$PROJ/$SID.jsonl" << JSONL
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Proceed"}]},"timestamp":"$TS3","sessionId":"$SID"}
JSONL
python3 -c "import json; d=json.load(open('$HOME/.claude/sessions/$FAKE_PID.json')); d['status']='idle'; json.dump(d,open('$HOME/.claude/sessions/$FAKE_PID.json','w'))"

echo "  → You should see 🟢 triple-flash + notification '完成'"
echo "  → Window should auto-expand if collapsed"
echo "  → Session stays visible until you click to dismiss"
sleep 6

echo ""
echo "=== Simulation complete ==="
echo "The simulated session will stay in the list until you click it."
echo "Run this script again to simulate another cycle."
sleep 10
