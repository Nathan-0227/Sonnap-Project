"""
llm_client.py — 呼叫 Claude API 的唯一入口

═══════════════════════════════════════════════════════════════════
為什麼用標準庫 urllib.request 而不裝官方 SDK
═══════════════════════════════════════════════════════════════════
專案規範明訂「優先用標準庫，非必要不加依賴」。garmin/ 那邊拒絕為了 15 行
的 .env 解析而裝 python-dotenv，同樣的邏輯在這裡更成立——

  **這整個 AI 功能不會讓 requirements.txt 多任何一行。**

⚠️ 誠實揭露代價：手寫 client 在 API 改版時會壞掉，而官方 SDK 會吸收那種變動。
   緩解方式是把所有 HTTP 細節關在這一個檔案裡、只對外露一個函式
   （complete_json），日後要換成 SDK 或換模型都是單檔改動。

═══════════════════════════════════════════════════════════════════
用到的 API 特性（2026-08 查證現行文件後確認）
═══════════════════════════════════════════════════════════════════
- Endpoint: POST https://api.anthropic.com/v1/messages
- 金鑰放 **header**（x-api-key），不放 URL query——query 會漏進 shell history
  與 proxy log。
- structured outputs：用 output_config.format 指定 JSON schema，由 API 保證
  回傳合法 JSON。**這比「在 prompt 裡拜託模型輸出 JSON 再自己驗證重試」可靠得多**，
  而且不需要引入 tool-use 的複雜度。schema 限制：物件必須有
  additionalProperties: false 與 required。
- **不送 temperature / top_p / top_k**——這些參數在 claude-opus-5 上會回 400。
  （所以本模組的輸出不是靠調 temperature 產生變化，見 README 的可重現性說明。）
- thinking 在 claude-opus-5 上**預設開啟**，且 max_tokens 是「思考 + 回覆」的
  總上限。這裡用 effort=low 壓低思考量並給足 max_tokens，避免回覆被截斷。
- stop_reason 可能是 "refusal"（安全分類器拒絕）——**必須先檢查 stop_reason
  再讀 content**，否則 content 是空的會直接爆掉。
"""

import json
import os
import time
import urllib.error
import urllib.request

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"

DEFAULT_MODEL = "claude-opus-5"
DEFAULT_MAX_TOKENS = 8000  # 思考 + 回覆的總量；輸出只有幾百字，這裡留足餘裕
DEFAULT_EFFORT = "low"     # 這是「照著事實區塊改寫文字」的任務，不需要深度推理
DEFAULT_TIMEOUT = 60       # 秒。沒設 timeout 時 socket 卡住會無限阻塞整條 pipeline

# 只對這些狀況重試。400/401/403 是設定錯誤，重試一萬次結果一樣，
# 只會浪費時間並讓錯誤訊息更難找。
RETRYABLE_STATUS = {408, 409, 429, 500, 502, 503, 504, 529}
RETRY_DELAYS = (2, 4)  # 兩次重試，間隔 2 秒、4 秒


class LLMError(Exception):
    """呼叫失敗。呼叫端據此決定要不要 fallback。"""


class LLMRefusal(LLMError):
    """模型的安全分類器拒絕了這個請求。重試同樣的內容不會有幫助。"""


def api_key_available() -> bool:
    """讓呼叫端能在完全不發請求的情況下先判斷「有沒有設定好」。"""
    return bool(os.getenv("ANTHROPIC_API_KEY", "").strip())


def model_name() -> str:
    return os.getenv("ANTHROPIC_MODEL", "").strip() or DEFAULT_MODEL


def complete_json(
    system_prompt: str,
    user_prompt: str,
    schema: dict,
    *,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    effort: str = DEFAULT_EFFORT,
    timeout: int = DEFAULT_TIMEOUT,
):
    """
    送一次請求，回傳 (parsed_dict, model_used)。

    schema 由 API 強制套用，所以回傳值保證是符合 schema 的 JSON——
    呼叫端不需要處理「模型回了一段散文」這種情況。

    失敗時丟 LLMError / LLMRefusal，不回傳半成品。
    """
    api_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        raise LLMError("Environment variable ANTHROPIC_API_KEY is not set")

    model = model_name()
    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "system": system_prompt,
        "messages": [{"role": "user", "content": user_prompt}],
        "output_config": {
            "effort": effort,
            "format": {"type": "json_schema", "schema": schema},
        },
    }

    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "x-api-key": api_key,
        "anthropic-version": API_VERSION,
        "content-type": "application/json",
    }

    last_error = None
    for attempt in range(len(RETRY_DELAYS) + 1):
        try:
            request = urllib.request.Request(
                API_URL, data=body, headers=headers, method="POST"
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8"))
            return _extract_json(data), model

        except urllib.error.HTTPError as exc:
            detail = _read_error_body(exc)
            if exc.code not in RETRYABLE_STATUS:
                # 設定錯誤：立刻放棄並回報，不要浪費重試次數
                raise LLMError(f"HTTP {exc.code}：{detail}") from exc
            last_error = LLMError(f"HTTP {exc.code}：{detail}")

        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise LLMError(f"connection failed: {exc}") from exc

        except json.JSONDecodeError as exc:
            # 回應不是合法 JSON——通常是中途被 proxy 截斷，值得重試一次
            raise LLMError(f"could not parse the response: {exc}") from exc

        if attempt < len(RETRY_DELAYS):
            time.sleep(RETRY_DELAYS[attempt])

    message = payload.get("error", {}).get("message", "unknown error")


def _extract_json(data: dict) -> dict:
    """從回應中取出結構化輸出。先檢查 stop_reason 再讀 content。"""
    stop_reason = data.get("stop_reason")

    if stop_reason == "refusal":
        details = data.get("stop_details") or {}
        raise LLMRefusal(
            f"model refused (category={details.get('category')})"
        )

    if stop_reason == "max_tokens":
        # 回覆被截斷 → JSON 不完整。當成失敗而不是勉強使用，
        # 因為半截的建議文字比沒有建議更糟。
        raise LLMError("response was truncated by max_tokens; raise max_tokens")

    for block in data.get("content") or []:
        if block.get("type") == "text":
            return json.loads(block["text"])

    raise LLMError(f"no text content in the response (stop_reason={stop_reason})")


def _read_error_body(exc: urllib.error.HTTPError) -> str:
    """把錯誤訊息挖出來。API 的錯誤格式是 {"error": {"message": ...}}。"""
    try:
        parsed = json.loads(exc.read().decode("utf-8"))
        return parsed.get("error", {}).get("message") or str(parsed)
    except Exception:
        detail = payload.get("error", {}).get("message", "(no error message)")
