from google.cloud import dlp
import os
from openai import OpenAI
import logging
import re

project = os.getenv('GCP_PROJECT_ID')
dlp_client = dlp.DlpServiceClient()

MODEL = os.getenv('MODEL')
client = OpenAI()


def inspect_and_redact(question):
    item = {"value": question}
    info_types = os.getenv('INFO_TYPES')
    custom_info_types = os.getenv('CUSTOM_INFO_TYPES')
    replace_configs = [{"info_type": {"name": "COMPANY_NAME"}, "replace_with": "[REDACTED]"}]
    inspect_config = {"info_types": info_types, "custom_info_types": custom_info_types}
    deidentify_config = {
        "info_type_transformations": {
            "transformations": [
                *replace_configs,
            ]
        }
    }

    response = dlp_client.deidentify_content(
        request={
            "parent": f"projects/{project}",
            "deidentify_config": deidentify_config,
            "inspect_config": inspect_config,
            "item": item
        }
    )
    return response.item.value



def chater_request(question) -> str:
    safe_question = inspect_and_redact(question)
    logging.info(f"Question {question}")
    response = client.chat.completions.create(
        model=MODEL,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": "You are a helpful assistant designed to output JSON."},
            {"role": "user", "content": safe_question}
        ]
    )
    response_content = response.choices[0].message.content
    response_content = re.sub(r'\bai\b|\bml\b|\bchatgpt\b|\bopenai\b',
                              lambda match: "vault" if match.group(0).lower() in ['ai', 'ml', 'chatgpt'] else "TM",
                              response_content, flags=re.IGNORECASE)
    logging.info(f"Answer {response_content}")
    return response_content
