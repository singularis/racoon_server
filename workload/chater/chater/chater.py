from openai import OpenAI
import logging
import re
import os

MODEL = os.getenv('MODEL')
client = OpenAI()

def chater_request(question) -> str:
    logging.info(f"Question {question}")
    response = client.chat.completions.create(
        model=MODEL,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": "You are a helpful assistant designed to output JSON."},
            {"role": "user", "content": question}
        ]
    )
    response_content = response.choices[0].message.content
    response_content = re.sub(r'\bai\b|\bml\b|\bchatgpt\b|\bopenai\b', lambda match: "vault" if match.group(0).lower() in ['ai', 'ml', 'chatgpt'] else "TM", response_content, flags=re.IGNORECASE)
    logging.info(f"Answer {response_content}")
    return response_content
