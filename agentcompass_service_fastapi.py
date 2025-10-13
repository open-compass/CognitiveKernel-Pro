#!/usr/bin/env python3

"""
FastAPI-based synchronous CognitiveKernel-Pro service.

Usage:
    pip install fastapi uvicorn
    uvicorn agentcompass_service_fastapi:app --host 0.0.0.0 --port 8080 --workers 4

Features:
- Synchronous execution (no threading/multiprocessing complexity)
- Multiple workers for concurrent request handling
- Each CKAgent runs in worker process main thread (no signal issues)
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict, Any
import os
import sys

# Ensure repo root is on sys.path
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from ck_pro.agents.utils import rprint

# Auto-load environment variables from .env at import time (works with uvicorn CLI)
def _load_env_file(path: str):
    try:
        with open(path, "r") as fd:
            for line in fd:
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                if s.startswith("export "):
                    s = s[len("export "):].strip()
                if "=" not in s:
                    continue
                k, v = s.split("=", 1)
                k = k.strip()
                v = v.strip()
                if (len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'")):
                    v = v[1:-1]
                os.environ[k] = v
        rprint(f"Loaded environment variables from {path}")
    except Exception as e:
        rprint(f"[warn] Failed to load env file {path}: {e}")

# Try to load from CWD then script directory
for _cand in (os.path.join(os.getcwd(), ".env"), os.path.join(os.path.dirname(__file__), ".env")):
    if os.path.isfile(_cand):
        _load_env_file(_cand)
        break

app = FastAPI(title="CognitiveKernel-Pro Service", version="1.0.0")

class TaskRequest(BaseModel):
    params: Optional[Dict[str, Any]] = None
    benchmark: Optional[str] = None
    llm_config: Optional[Dict[str, Any]] = None
    modality: Optional[str] = None

class TaskResponse(BaseModel):
    final_answer: str
    trajectory: Optional[list] = None
    call_stat: Optional[Dict[str, Any]] = None

# Recursively convert nested objects (e.g., AgentResult, ActionResult, AgentSession)
# into JSON-serializable structures. Falls back to repr() for unknown objects.
def _json_sanitize(obj):
    # Primitives
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj
    # Dict
    if isinstance(obj, dict):
        return {str(k): _json_sanitize(v) for k, v in obj.items()}
    # Sequences and sets
    if isinstance(obj, (list, tuple, set)):
        return [_json_sanitize(x) for x in obj]
    # Custom objects with to_dict
    to_dict = getattr(obj, "to_dict", None)
    if callable(to_dict):
        try:
            return _json_sanitize(to_dict())
        except Exception:
            return repr(obj)
    # Fallback: use repr
    try:
        return repr(obj)
    except Exception:
        return str(obj)

def _extract_prompt(payload: dict) -> str:
    params = payload.get('params') or {}
    val = params.get('question') or params.get('query')
    return val.strip() if isinstance(val, str) else ''

def _extract_dataset(payload: dict) -> str:
    val = payload.get('benchmark') if isinstance(payload, dict) else ''
    return val.strip() if isinstance(val, str) else ''

def _extract_file_name(payload: dict) -> str:
    params = payload.get('params') or {}
    meta = params.get('metadata') if isinstance(params, dict) else None
    val = meta.get('file_name') if isinstance(meta, dict) else ''
    return val.strip() if isinstance(val, str) else ''

def _extract_modality(payload: dict) -> str:
    """Extract modality from top-level request only, normalized to lowercase string."""
    val = payload.get('modality') if isinstance(payload, dict) else None
    if isinstance(val, str):
        return val.strip().lower()
    return 'llm'

def _resolve_data_file(file_name: str) -> str:
    """Resolve a data file by simply joining with data base directory."""
    if not file_name:
        return ''
    base = os.path.join(_REPO_ROOT, 'CognitiveKernel-Pro/data')
    cand = os.path.join(base, file_name)
    return os.path.abspath(cand) if os.path.isfile(cand) else ''

def _ck_kwargs_from_llm_config(cfg: dict) -> dict:
    """Translate llm_config from AgentCompass into CKAgent(**kwargs)."""
    ck_kwargs: dict = {}
    if not isinstance(cfg, dict):
        return ck_kwargs

    model_name = cfg.get("model_name")
    url = cfg.get("url")
    api_key = cfg.get("api_key")
    model_cfg_dict = cfg.get("model_config_dict")
    request_timeout = cfg.get("request_timeout")

    ct = cfg.get("call_target")
    if not ct:
        if isinstance(model_name, str) and model_name:
            ct = model_name if model_name.startswith("gpt:") else f"gpt:{model_name}"

    call_kwargs = dict(model_cfg_dict) if isinstance(model_cfg_dict, dict) else {}
    if url:
        call_kwargs["api_base"] = url
    if api_key:
        call_kwargs["api_key"] = api_key

    model_cfg = {}
    if ct:
        model_cfg["call_target"] = ct
    if call_kwargs:
        model_cfg["call_kwargs"] = call_kwargs
    if isinstance(request_timeout, (int, float)) and request_timeout > 0:
        model_cfg["request_timeout"] = int(request_timeout)

    if model_cfg:
        ck_kwargs["model"] = model_cfg

    # Also enforce server-side execution limits so the worker is freed on timeout
    if isinstance(request_timeout, (int, float)) and request_timeout > 0:
        t = int(request_timeout)
        ck_kwargs["max_time_limit"] = t
        ck_kwargs["exec_timeout_with_call"] = t
        ck_kwargs["exec_timeout_wo_call"] = t
        ck_kwargs["_task_timeout"] = t

    return ck_kwargs

def _apply_default_subagents(ck_kwargs: dict) -> dict:
    """Set sub-agents exactly like example_run_llm.sh MAIN_ARGS."""
    if not isinstance(ck_kwargs, dict):
        ck_kwargs = {}

    model_cfg = ck_kwargs.get('model') or {}
    call_target = model_cfg.get('call_target')
    top_call_kwargs = model_cfg.get('call_kwargs') if isinstance(model_cfg.get('call_kwargs'), dict) else None
    web_ip = os.getenv('WEB_IP', 'localhost:3001')

    web_model = {}
    if call_target:
        web_model['call_target'] = call_target
    if top_call_kwargs:
        web_model['call_kwargs'] = dict(top_call_kwargs)

    file_model = {}
    if call_target:
        file_model['call_target'] = call_target
    if top_call_kwargs:
        file_model['call_kwargs'] = dict(top_call_kwargs)

    # Build web env kwargs and propagate timeout if provided
    web_env_kwargs = {'web_ip': web_ip}
    _t = ck_kwargs.pop('_task_timeout', None)
    if isinstance(_t, int) and _t > 0:
        web_env_kwargs['web_timeout'] = _t

    ck_kwargs['web_agent'] = {
        'use_multimodal': 'no',
        'model': web_model,
        'web_env_kwargs': web_env_kwargs,
    }
    ck_kwargs['file_agent'] = {
        'model': file_model,
    }
    return ck_kwargs

@app.post("/api/tasks", response_model=TaskResponse)
async def run_task(request: TaskRequest):
    """Run CKAgent synchronously and return result immediately."""
    payload = request.model_dump()

    prompt = _extract_prompt(payload)
    if not prompt:
        raise HTTPException(status_code=400, detail="empty prompt")

    try:
        # Resolve optional dataset, modality, and file_name
        dataset = _extract_dataset(payload)
        _ = _extract_modality(payload)
        file_name = _extract_file_name(payload)
        input_file = ''
        if file_name:
            input_file = _resolve_data_file(file_name)
            if not input_file:
                raise HTTPException(
                    status_code=400,
                    detail=f"input file not found under data (dataset={dataset}, file_name={file_name})"
                )

        task_text = prompt
        if input_file:
            task_text = f"{prompt}\n(* You are given the following input file: {input_file})"

        # Import and run CKAgent (in worker process main thread - no signal issues)
        from ck_pro.ck_main.agent import CKAgent
        llm_cfg = payload.get('llm_config')
        ck_kwargs = _ck_kwargs_from_llm_config(llm_cfg)
        ck_kwargs = _apply_default_subagents(ck_kwargs)

        agent = CKAgent(**ck_kwargs) if ck_kwargs else CKAgent()
        res = agent.run(task_text)
        # Collect token usage statistics and attach to session/info
        call_stat = agent.get_call_stat(clear=True)
        raw_sess = res.to_dict() if hasattr(res, 'to_dict') else {}
        if isinstance(raw_sess, dict):
            info = raw_sess.get('info') or {}
            info['call_stat'] = call_stat
            raw_sess['info'] = info
            # Also inject call_stat into the last step's end, so it appears in trajectory
            try:
                if isinstance(raw_sess.get('steps'), list) and raw_sess['steps']:
                    end_obj = raw_sess['steps'][-1].get('end')
                    if isinstance(end_obj, dict):
                        end_obj['call_stat'] = call_stat
            except Exception:
                pass
        sess = _json_sanitize(raw_sess)

        # # Print token stats to logs similar to example_run_llm.sh pipeline
        # try:
        #     _all = call_stat.get('__ALL__', {}) if isinstance(call_stat, dict) else {}
        #     rprint(f"Token-CC __ALL__: {_all}")
        #     if isinstance(call_stat, dict):
        #         for _k, _v in call_stat.items():
        #             if _k != '__ALL__':
        #                 rprint(f"Token-CC {_k}: {_v}")
        # except Exception:
        #     pass

        # Extract final answer
        try:
            final_answer = str(sess['steps'][-1]['end']['final_results']['output'])
        except Exception:
            raise HTTPException(status_code=500, detail="failed to extract final answer")

        trajectory = sess.get('steps', []) if isinstance(sess, dict) else []
        trajectory = _json_sanitize(trajectory)

        return TaskResponse(final_answer=final_answer, trajectory=trajectory, call_stat=_json_sanitize(call_stat))

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    import argparse
    import os

    parser = argparse.ArgumentParser(description="FastAPI server for CognitiveKernel-Pro")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on (default: 8080)")
    parser.add_argument("--workers", type=int, default=1, help="Number of worker processes (default: 1)")
    args = parser.parse_args()

    # When using multiple workers, uvicorn requires the app to be provided as an import string
    # so that each worker process can import it. Otherwise it warns and ignores workers>1.
    module_name = os.path.splitext(os.path.basename(__file__))[0]  # e.g., 'agentcompass_service_fastapi'
    app_target = f"{module_name}:app" if (args.workers and args.workers > 1) else app

    uvicorn.run(app_target, host=args.host, port=args.port, workers=args.workers)
