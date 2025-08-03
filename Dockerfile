FROM ubuntu:jammy

# Install system dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    wget \
    build-essential \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python 3.12.11
RUN wget https://www.python.org/ftp/python/3.12.11/Python-3.12.11.tgz \
    && tar xzf Python-3.12.11.tgz \
    && cd Python-3.12.11 \
    && ./configure --enable-optimizations \
    && make altinstall \
    && cd .. \
    && rm -rf Python-3.12.11 Python-3.12.11.tgz

# Create symlinks for python and pip
RUN ln -s /usr/local/bin/python3.12 /usr/local/bin/python \
    && ln -s /usr/local/bin/pip3.12 /usr/local/bin/pip

# Install Python libraries
RUN pip install --no-cache-dir \
    fastmcp \
    python-jose \
    httpx \
    pytest \
    fastapi \
    uvicorn \
    pyjwt \
    mcpo \
    litellm[proxy]

# Set working directory
WORKDIR /app

# Copy the entrypoint script
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

# Create mcp_server directory and copy files
RUN mkdir -p mcp_server
COPY secure_mcp/server.py ./mcp_server/server.py
COPY secure_mcp/store.py ./mcp_server/store.py
COPY secure_mcp/mcp_test_client.py ./mcp_server/mcp_test_client.py
COPY litellm-config.yaml ./litellm-config.yaml

# Set entrypoint
ENTRYPOINT ["./entrypoint.sh"]