# syntax=docker/dockerfile:1
#
# targeting-service (Python/Flask) — build multi-stage.
# Estágio 1 monta um virtualenv; estágio 2 copia só o venv, sem toolchain de build.

# ---------- estágio 1: dependências ----------
FROM python:3.11-slim AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
# constraints.txt trava o Werkzeug em 2.x — ver constraints.txt para o porquê.
COPY requirements.txt constraints.txt ./
RUN pip install -r requirements.txt -c constraints.txt

# ---------- estágio 2: runtime ----------
FROM python:3.11-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN useradd --create-home --uid 10001 app

COPY --from=build /opt/venv /opt/venv

WORKDIR /app
COPY --chown=app:app app.py ./

USER app
EXPOSE 8003

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8003/health', timeout=2).status == 200 else 1)"]

# 2 workers x 4 threads: o serviço é I/O-bound (Postgres (regras JSONB) + chamada ao auth-service).
CMD ["gunicorn", "--bind", "0.0.0.0:8003", \
     "--workers", "2", "--threads", "4", \
     "--access-logfile", "-", "--error-logfile", "-", \
     "app:app"]
