FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app/comms
# No secrets here: the platform injects FOUNDRY_PROJECT_ENDPOINT and the agent identity at runtime.
EXPOSE 8088
CMD ["python", "-m", "comms.main"]
