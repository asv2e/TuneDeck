FROM python:3.13-slim

# Deno is the JavaScript runtime yt-dlp uses to solve YouTube's player challenges.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY resolver.py .

EXPOSE 8787
CMD ["python", "resolver.py"]
