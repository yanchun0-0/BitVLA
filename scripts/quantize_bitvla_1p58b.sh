#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/quantize_bitvla_1p58b.sh [--bitnet-dir DIR] [--model-path PATH] [--output-dir DIR] [--quant-type TYPE]

Defaults:
  --bitnet-dir  ./bitnet
  --model-path  auto-detect from HF cache for hongyuw/bitvla-bitsiglipL-224px-bf16
  --output-dir  ./bitvla-1p58b-gguf
  --quant-type  i2_s

Environment overrides:
  BITNET_DIR, MODEL_PATH, OUTPUT_DIR, QUANT_TYPE
  BITNET_SETUP_ARGS (extra args passed to setup_env.py)

Notes:
  * This script wraps the BitNet setup_env.py flow to convert HF -> GGUF and quantize.
  * It attempts to infer the correct CLI flags by parsing `setup_env.py --help`.
USAGE
}

BITNET_DIR=${BITNET_DIR:-""}
MODEL_PATH=${MODEL_PATH:-""}
OUTPUT_DIR=${OUTPUT_DIR:-""}
QUANT_TYPE=${QUANT_TYPE:-""}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bitnet-dir)
      BITNET_DIR="$2"
      shift 2
      ;;
    --model-path)
      MODEL_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --quant-type)
      QUANT_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
 done

BITNET_DIR=${BITNET_DIR:-"/workspace/BitVLA/bitnet"}
OUTPUT_DIR=${OUTPUT_DIR:-"/workspace/BitVLA/bitvla-1p58b-gguf"}
QUANT_TYPE=${QUANT_TYPE:-"i2_s"}

if [[ -z "$MODEL_PATH" ]]; then
  candidate_base="$HOME/.cache/huggingface/hub/models--hongyuw--bitvla-bitsiglipL-224px-bf16/snapshots"
  if [[ -d "$candidate_base" ]]; then
    latest_snapshot=$(ls -td "$candidate_base"/* 2>/dev/null | head -n 1 || true)
    if [[ -n "$latest_snapshot" ]]; then
      MODEL_PATH="$latest_snapshot"
    fi
  fi
fi

if [[ -z "$MODEL_PATH" ]]; then
  echo "ERROR: MODEL_PATH is not set and the HF cache was not found." >&2
  echo "Set MODEL_PATH to the local path of hongyuw/bitvla-bitsiglipL-224px-bf16." >&2
  exit 1
fi

if [[ ! -d "$BITNET_DIR" ]]; then
  cat <<BITNET_EOF >&2
ERROR: BITNET_DIR does not exist: $BITNET_DIR

Clone the BitNet repo and retry, e.g.:
  git clone https://github.com/microsoft/BitNet.git "$BITNET_DIR"
BITNET_EOF
  exit 1
fi

if [[ ! -f "$BITNET_DIR/setup_env.py" ]]; then
  echo "ERROR: $BITNET_DIR/setup_env.py not found. Is this the BitNet repo root?" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

help_text=$(python "$BITNET_DIR/setup_env.py" --help 2>&1 || true)

pick_flag() {
  local flag
  for flag in "$@"; do
    if echo "$help_text" | grep -q -- "$flag"; then
      echo "$flag"
      return 0
    fi
  done
  return 1
}

model_flag=$(pick_flag "--model-path" "--model" "--hf-model" "--hf-model-path" "--model-dir" || true)
output_flag=$(pick_flag "--output-dir" "--out-dir" "--outdir" "--output" || true)
quant_flag=$(pick_flag "--quant-type" "--quant" "--quantization" "--quant-method" || true)

cmd=(python "$BITNET_DIR/setup_env.py")

if [[ -n "$model_flag" ]]; then
  cmd+=("$model_flag" "$MODEL_PATH")
else
  cmd+=("$MODEL_PATH")
fi

if [[ -n "$output_flag" ]]; then
  cmd+=("$output_flag" "$OUTPUT_DIR")
else
  cmd+=("--output" "$OUTPUT_DIR")
fi

if [[ -n "$quant_flag" ]]; then
  cmd+=("$quant_flag" "$QUANT_TYPE")
else
  cmd+=("--quant-type" "$QUANT_TYPE")
fi

if [[ -n "${BITNET_SETUP_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  cmd+=( ${BITNET_SETUP_ARGS} )
fi

printf 'Running: %q ' "${cmd[@]}"
printf '\n'
"${cmd[@]}"

cat <<DONE_EOF

Done. Quantized GGUF should be under:
  $OUTPUT_DIR
DONE_EOF
