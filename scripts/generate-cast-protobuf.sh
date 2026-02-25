#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="$ROOT_DIR/Protos/CastV2"
PROTO_FILE="$PROTO_DIR/cast_channel.proto"
OUTPUT_DIR="${1:-$ROOT_DIR/Sources/ChromecastKit/Internal/Transport/CastV2/Generated}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Generate optional SwiftProtobuf models for the Cast v2 channel envelope.

Usage:
  scripts/generate-cast-protobuf.sh [output-directory]

Defaults:
  output-directory = Sources/ChromecastKit/Internal/Transport/CastV2/Generated

Requirements:
  - protoc
  - protoc-gen-swift (SwiftProtobuf plugin)

Examples:
  brew install protobuf swift-protobuf
  scripts/generate-cast-protobuf.sh
USAGE
  exit 0
fi

if [[ ! -f "$PROTO_FILE" ]]; then
  echo "Missing proto file: $PROTO_FILE" >&2
  exit 1
fi

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc not found. Install with: brew install protobuf" >&2
  exit 1
fi

if ! command -v protoc-gen-swift >/dev/null 2>&1; then
  echo "protoc-gen-swift not found. Install with: brew install swift-protobuf" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$OUTPUT_DIR" \
  "$PROTO_FILE"

echo "Generated Swift protobuf envelope models in: $OUTPUT_DIR"
