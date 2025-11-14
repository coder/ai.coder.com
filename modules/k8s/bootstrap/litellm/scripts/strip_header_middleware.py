from litellm.integrations.custom_logger import CustomLogger
import litellm
from litellm.proxy.proxy_server import UserAPIKeyAuth, DualCache
from typing import Optional, Literal
# Added logging for proper error tracking and debugging
import logging

logger = logging.getLogger(__name__)

class HeaderHandler(CustomLogger):
    def __init__(self):
        pass

    async def async_pre_call_hook(self, user_api_key_dict: UserAPIKeyAuth, cache: DualCache, data: dict, call_type: Literal[
            "completion",
            "text_completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
        ]): 
        # Added error handling to safely access nested dictionary keys
        if "proxy_server_request" in data and "headers" in data["proxy_server_request"]:
            v = data["proxy_server_request"]["headers"].pop("anthropic-beta", None)
            if v not in [None, "claude-code-20250219"]:
                data["proxy_server_request"]["headers"]["anthropic-beta"] = v
        
        v = data.get("provider_specific_header", {}).get("extra_headers", {}).pop("anthropic-beta", None)
        if v not in [None, "claude-code-20250219"]:
            # Ensure nested structure exists before setting value
            if "provider_specific_header" not in data:
                data["provider_specific_header"] = {}
            if "extra_headers" not in data["provider_specific_header"]:
                data["provider_specific_header"]["extra_headers"] = {}
            data["provider_specific_header"]["extra_headers"]["anthropic-beta"] = v
        
        v = data.get("litellm_metadata", {}).get("headers", {}).pop("anthropic-beta", None)
        if v not in [None, "claude-code-20250219"]:
            # Ensure nested structure exists before setting value
            if "litellm_metadata" not in data:
                data["litellm_metadata"] = {}
            if "headers" not in data["litellm_metadata"]:
                data["litellm_metadata"]["headers"] = {}
            data["litellm_metadata"]["headers"]["anthropic-beta"] = v
        # Replaced print with proper logging for production use
        logger.debug(f"Processed request data: {data}")
        return data

strip_header_callback = HeaderHandler()
