FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    vim \
    curl \
    && apt-get clean
RUN useradd -m app
USER app

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python3", "/app/app.py"]