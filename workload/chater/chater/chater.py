import os
from openai import OpenAI
import logging
import re
from dlp import INFO_TYPES
from google.cloud import dlp_v2
from google.cloud.dlp_v2.types import DeidentifyConfig, InfoTypeTransformations, PrimitiveTransformation, \
    ReplaceValueConfig

MODEL = os.getenv('MODEL')
client = OpenAI()


def inspect_and_redact(question: str) -> str:
    dlp = dlp_v2.DlpServiceClient()
    project_id = os.getenv('GCP_PROJECT_ID')

    item = {"value": question}

    info_types = INFO_TYPES
    inspect_config = {"info_types": info_types}

    replace_config = ReplaceValueConfig(new_value={"string_value": "[REDACTED]"})
    primitive_transformation = PrimitiveTransformation(replace_config=replace_config)

    # Define the info type transformations
    info_type_transformations = InfoTypeTransformations(
        transformations=[{
            "info_types": info_types,
            "primitive_transformation": primitive_transformation
        }]
    )
    deidentify_config = DeidentifyConfig(
        info_type_transformations=info_type_transformations
    )

    # Call the DLP API
    response = dlp.deidentify_content(
        request={
            "parent": f"projects/{project_id}",
            "inspect_config": inspect_config,
            "item": item,
            "deidentify_config": deidentify_config,
        }
    )
    logging.info(f"Response from DLP {response.item.value}")
    return response.item.value


def chater_request(question) -> dict[str, str]:
    safe_question = inspect_and_redact(question)
    logging.info(f"Original {question}")
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
    logging.info(f"GPT Answer {response_content}")
    return {"response_content": response_content, "safe_question": safe_question}
