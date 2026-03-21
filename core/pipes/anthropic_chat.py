"""
Anthropic manifold pipeline for OpenWebUI.
Exposes Claude models through the pipelines server.

Based on: https://github.com/open-webui/pipelines/blob/main/examples/pipelines/providers/anthropic_manifold_pipeline.py
requirements: requests, sseclient-py
environment_variables: ANTHROPIC_API_KEY
"""

import os
import json
import logging
import requests
import sseclient
from typing import List, Union, Generator, Iterator, Tuple
from pydantic import BaseModel

logging.getLogger().setLevel(logging.WARNING)

REASONING_EFFORT_BUDGET_TOKEN_MAP = {
    "none": None,
    "low": 1024,
    "medium": 4096,
    "high": 16384,
    "max": 32768,
}

MAX_COMBINED_TOKENS = 64000


def pop_system_message(messages: List[dict]) -> Tuple[dict | None, List[dict]]:
    system = None
    filtered = []
    for msg in messages:
        if msg["role"] == "system":
            system = msg
        else:
            filtered.append(msg)
    return system, filtered


class Pipeline:
    class Valves(BaseModel):
        ANTHROPIC_API_KEY: str = ""

    def __init__(self):
        self.type = "manifold"
        self.id = "claude"
        self.name = "anthropic/"

        self.valves = self.Valves(
            ANTHROPIC_API_KEY=os.getenv("ANTHROPIC_API_KEY", ""),
        )
        self.url = "https://api.anthropic.com/v1/messages"
        self.update_headers()

    def update_headers(self):
        self.headers = {
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
            "x-api-key": self.valves.ANTHROPIC_API_KEY,
        }

    def get_anthropic_models(self):
        return [
            {"id": "claude-sonnet-4-20250514", "name": "claude-4.0-sonnet"},
            {"id": "claude-opus-4-20250514", "name": "claude-4.0-opus"},
            {"id": "claude-opus-4-6", "name": "claude-4.6-opus"},
        ]

    async def on_startup(self):
        pass

    async def on_shutdown(self):
        pass

    async def on_valves_updated(self):
        self.update_headers()

    def pipelines(self) -> List[dict]:
        return self.get_anthropic_models()

    def process_image(self, image_data):
        if image_data["url"].startswith("data:image"):
            mime_type, base64_data = image_data["url"].split(",", 1)
            media_type = mime_type.split(":")[1].split(";")[0]
            return {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": media_type,
                    "data": base64_data,
                },
            }
        else:
            return {
                "type": "image",
                "source": {"type": "url", "url": image_data["url"]},
            }

    def pipe(
        self, user_message: str, model_id: str, messages: List[dict], body: dict
    ) -> Union[str, Generator, Iterator]:
        try:
            for key in ["user", "chat_id", "title"]:
                body.pop(key, None)

            system_message, messages = pop_system_message(messages)

            processed_messages = []
            image_count = 0

            for message in messages:
                processed_content = []
                if isinstance(message.get("content"), list):
                    for item in message["content"]:
                        if item["type"] == "text":
                            processed_content.append(
                                {"type": "text", "text": item["text"]}
                            )
                        elif item["type"] == "image_url":
                            if image_count >= 5:
                                raise ValueError("Maximum of 5 images per API call")
                            processed_content.append(
                                self.process_image(item["image_url"])
                            )
                            image_count += 1
                else:
                    processed_content = [
                        {"type": "text", "text": message.get("content", "")}
                    ]

                processed_messages.append(
                    {"role": message["role"], "content": processed_content}
                )

            payload = {
                "model": model_id,
                "messages": processed_messages,
                "max_tokens": body.get("max_tokens", 4096),
                "temperature": body.get("temperature", 0.8),
                "top_k": body.get("top_k", 40),
                "stop_sequences": body.get("stop", []),
                **({"system": str(system_message["content"])} if system_message else {}),
                "stream": body.get("stream", False),
            }

            if body.get("stream", False):
                return self.stream_response(payload)
            else:
                return self.get_completion(payload)
        except Exception as e:
            return f"Error: {e}"

    def stream_response(self, payload: dict) -> Generator:
        try:
            response = requests.post(
                self.url, headers=self.headers, json=payload, stream=True
            )

            if response.status_code == 200:
                client = sseclient.SSEClient(response)
                for event in client.events():
                    try:
                        data = json.loads(event.data)
                        if data["type"] == "content_block_start":
                            if data["content_block"]["type"] == "thinking":
                                yield "<think>"
                            else:
                                yield data["content_block"].get("text", "")
                        elif data["type"] == "content_block_delta":
                            if data["delta"]["type"] == "thinking_delta":
                                yield data["delta"]["thinking"]
                            elif data["delta"]["type"] == "signature_delta":
                                yield "\n</think>\n\n"
                            else:
                                yield data["delta"].get("text", "")
                        elif data["type"] == "message_stop":
                            break
                    except KeyError:
                        continue
            else:
                yield f"Error: {response.status_code} - {response.text}"
        except Exception as e:
            yield f"Error: {e}"

    def get_completion(self, payload: dict) -> str:
        try:
            response = requests.post(self.url, headers=self.headers, json=payload)
            if response.status_code == 200:
                res = response.json()
                for content in res["content"]:
                    if content.get("text"):
                        return content["text"]
                return ""
            else:
                return f"Error: {response.status_code} - {response.text}"
        except Exception as e:
            return f"Error: {e}"
