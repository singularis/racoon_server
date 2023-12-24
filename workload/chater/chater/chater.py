from openai import OpenAI
import logging
import re

client = OpenAI()


def chater_request(question) -> str:
    logging.info(f"Question {question}")
    response = client.chat.completions.create(
        model="gpt-4-1106-preview",
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": "You are a helpful assistant designed to output JSON."},
            {"role": "user", "content": question}
        ]
    )
    response_content = response.choices[0].message.content
    response_content = re.sub(r'\bai\b|\bml\b|\bchatgpt\b', 'vault', response_content, flags=re.IGNORECASE)
    logging.info(f"Answer {response_content}")
    return response_content
