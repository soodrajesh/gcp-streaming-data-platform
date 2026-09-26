FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /srv
COPY app/requirements.txt app/requirements.txt
RUN pip install -r app/requirements.txt
COPY app app
RUN useradd -r -u 10001 app
USER 10001
# the Cloud Run service overrides this with gunicorn; the job runs `python -m app.generator`
CMD ["gunicorn", "--bind=:8080", "--workers=1", "--threads=8", "app.enricher:app"]
