# Development Guide

This document provides detailed instructions for setting up the development environment, installing dependencies, and running tests.

## Setup & Installation

### Prerequisites

- Python 3.11+
- Kubernetes cluster (1.24+) or Docker for local development
- Redis
- S3 storage (or S3-compatible storage)
- Helm 3.x (for Kubernetes deployment)

### Installation Steps

1. **Clone the repository**

   ```bash
   git clone https://github.com/K8sInterpreter/K8sInterpreter.git
   cd K8sInterpreter
   ```

2. **Create a virtual environment**

   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**

   ```bash
   pip install -r requirements.txt
   ```

4. **Set up environment variables**

   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Start infrastructure services**

   ```bash
   docker-compose up -d
   ```

6. **Run the API server**
   ```bash
   uvicorn src.main:app --reload
   ```

## Testing

For detailed testing instructions, please refer to [TESTING.md](TESTING.md).

### Quick Commands

```bash
# Run unit tests
pytest tests/unit/

# Run integration tests (requires Docker/Redis/S3 storage)
pytest tests/integration/

# Run all tests with coverage
pytest --cov=src tests/
```

## Building Container Images

The API requires language-specific execution images and the HTTP sidecar image.

```bash
# Build all language execution images
cd docker && ./build-images.sh -p && cd ..

# Build a single language image (e.g., Python)
cd docker && ./build-images.sh -l python && cd ..

# Build the HTTP sidecar image
cd docker/sidecar && docker build -t k8sinterpreter/sidecar:latest . && cd ../..
```

For more details on Kubernetes pod management, see [ARCHITECTURE.md](ARCHITECTURE.md).
