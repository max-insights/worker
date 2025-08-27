FROM mambaorg/micromamba:debian-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create the environment from the environment.yml
# The micromamba entrypoint automatically activates the base env
COPY environment.yml environment.yml
RUN micromamba install -y -n base -f environment.yml && \
    micromamba clean -y --all

CMD ["echo", "Container is set up. Replace this command with your application start command."]
