FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/rds-ca.pem
RUN chmod 644 /app/rds-ca.pem
COPY application /app/application
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn","application.api:app","--host","0.0.0.0","--port","8080","--workers","1"]
