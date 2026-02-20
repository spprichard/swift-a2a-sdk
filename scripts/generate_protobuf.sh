#!/bin/bash
# Script to generate Swift protobuf code from a2a.proto
# Requires protoc and protoc-gen-swift to be installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_DIR="$PROJECT_ROOT/../A2A/specification/grpc"
OUT_DIR="$PROJECT_ROOT/Sources/A2A/Protobuf"

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed"
    echo "Install from: https://grpc.io/docs/protoc-installation/"
    exit 1
fi

# Check if protoc-gen-swift is installed
if ! command -v protoc-gen-swift &> /dev/null; then
    echo "Error: protoc-gen-swift is not installed"
    echo "Install from: https://github.com/apple/swift-protobuf"
    echo "Or via Homebrew: brew install swift-protobuf"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Generate Swift code
echo "Generating Swift protobuf code..."
protoc \
    --swift_out=Visibility=Public:"$OUT_DIR" \
    --proto_path="$PROTO_DIR" \
    --proto_path="$PROTO_DIR/../../.." \
    "$PROTO_DIR/a2a.proto"

echo "Swift protobuf code generated successfully in $OUT_DIR"

