#!/bin/bash
# Bash script to convert Firebase service account JSON to single line
# Usage: ./convert-firebase-json.sh path/to/firebase-service-account.json

if [ $# -eq 0 ]; then
    echo "Error: Please provide the path to the Firebase JSON file"
    echo "Usage: $0 path/to/firebase-service-account.json"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File not found: $INPUT_FILE"
    exit 1
fi

echo "Reading Firebase JSON from: $INPUT_FILE"

# Remove all line breaks and save to file
cat "$INPUT_FILE" | tr -d '\n' > firebase-single-line.txt

# Also display to console
echo ""
echo "=== Single-line JSON (copy this) ==="
cat firebase-single-line.txt
echo ""
echo "=== End ==="
echo ""
echo "Saved to: firebase-single-line.txt"
echo "You can now copy the JSON above and paste it into Railway/Render environment variables."
