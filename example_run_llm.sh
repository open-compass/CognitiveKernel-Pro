#!/usr/bin/env bash
set -euo pipefail

# LLM-only example (no multimodal)
export PYTHONPATH="$(pwd)"
WEB_IP=localhost:3001

# Use gpt: mode with your vLLM OpenAI-compatible endpoint
export LLM_URL="gpt:qwen3-235b-thinking"
export OPENAI_ENDPOINT="https://sd1lpbei9optek6oou0s0.apigateway-cn-beijing.volceapi.com/v1"
export OPENAI_API_KEY="EMPTY"  # replace if your vLLM enables auth

mkdir -p test_output

MAIN_ARGS="{'web_agent': {'use_multimodal': 'no', 'model': {'call_target': '${LLM_URL}'}, 'web_env_kwargs': {'web_ip': '${WEB_IP}'}}, 'file_agent': {'model': {'call_target': '${LLM_URL}'}}, 'model': {'call_target': '${LLM_URL}'}}"

# You can remove -mpdb to run without debugger; remove --input to type from stdin
NO_NULL_STDIN=1 python3 -u -m ck_pro.ck_main.main \
  --updates "${MAIN_ARGS}" \
  --input ck_pro/ck_main/_test/simple_test.jsonl \
  --output test_output/simple_test.llm.output.jsonl |& tee _log_simple_test_llm

less -R _log_simple_test_llm  # colored output
