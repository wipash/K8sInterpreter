# LibreCodeInterpreter Architecture

## Overview

LibreCodeInterpreter is a secure API for executing code in isolated Kubernetes pods. It uses a **Kubernetes-native architecture** with warm pod pools for low-latency execution and Jobs for cold-path languages.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LibreCodeInterpreter API                             │
│                         (FastAPI Application)                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
            │   Redis     │  │    MinIO    │  │ Kubernetes  │
            │  (Sessions) │  │   (Files)   │  │   (Pods)    │
            └─────────────┘  └─────────────┘  └─────────────┘
                                                    │
                                    ┌───────────────┴───────────────┐
                                    ▼                               ▼
                            ┌─────────────────────┐       ┌─────────────────────┐
                            │     Pod Pool        │       │    Job Executor     │
                            │  (poolSize > 0)     │       │   (poolSize = 0)    │
                            │  Python, JS, etc.   │       │   Go, Rust, etc.    │
                            └─────────────────────┘       └─────────────────────┘
                                    │                               │
                                    ▼                               ▼
                            ┌─────────────────────────────────────────────┐
                            │              Execution Pods                  │
                            │  ┌─────────────────────────────────────┐    │
                            │  │  Main Container    │  HTTP Sidecar  │    │
                            │  │  (Language Runtime)│  (Executor)    │    │
                            │  └─────────────────────────────────────┘    │
                            └─────────────────────────────────────────────┘
```

## Execution Strategies

| Strategy | Cold Start | Use Case |
|----------|-----------|----------|
| **Warm Pod Pool** | 50-100ms | Languages with `pod_pool_<lang> > 0` |
| **Kubernetes Jobs** | 3-10s | Languages with `pod_pool_<lang> = 0` |

The warm pool approach achieves ~85% reduction in P99 latency compared to cold-start execution.

## Pod Design: Two-Container Sidecar Pattern

Each execution pod contains two containers:

### 1. Main Container (Language Runtime)
- Runs the language runtime (Python, Node.js, Go, etc.)
- Executes user code in isolation
- Shares `/mnt/data` volume with sidecar

### 2. HTTP Sidecar (Executor)
- Lightweight FastAPI server
- Exposes REST API for code execution
- Handles file transfers and state management

**Sidecar API Endpoints:**
```
POST /execute     - Execute code with optional state
POST /files       - Upload files to shared volume
GET  /files       - List files in working directory
GET  /files/{name} - Download file content
GET  /health      - Health check
```

## Core Components

### API Layer (`src/api/`)

| Module | Purpose |
|--------|---------|
| `exec.py` | Code execution endpoints (`POST /exec`) |
| `files.py` | File upload/download endpoints |
| `health.py` | Health and readiness checks |
| `state.py` | Session state management |
| `admin.py` | Admin dashboard API |

### Services Layer (`src/services/`)

| Service | Module | Responsibility |
|---------|--------|----------------|
| **SessionService** | `session.py` | Session lifecycle (create, get, delete) |
| **FileService** | `file.py` | File storage in MinIO |
| **CodeExecutionService** | `execution/` | Orchestrates code execution |
| **KubernetesManager** | `kubernetes/` | Pod lifecycle and execution |
| **StateService** | `state.py` | Python state persistence in Redis |
| **HealthService** | `health.py` | Service health monitoring |

### Kubernetes Module (`src/services/kubernetes/`)

| Component | Module | Responsibility |
|-----------|--------|----------------|
| **KubernetesManager** | `manager.py` | Main entry point, coordinates pools and jobs |
| **PodPoolManager** | `pool.py` | Warm pod pool management per language |
| **JobExecutor** | `job_executor.py` | Job-based execution for cold languages |
| **Client** | `client.py` | Kubernetes client factory |

## Data Flow: Code Execution

```
1. Client Request
   │
   ▼
2. API Endpoint (/exec)
   │
   ▼
3. ExecutionOrchestrator
   ├── Validate request
   ├── Get/create session
   ├── Load state (Python only)
   ├── Mount files
   │
   ▼
4. KubernetesManager.execute_code()
   ├── Hot path: Acquire pod from pool
   │   └── PodPoolManager.acquire()
   │
   └── Cold path: Create Job
       └── JobExecutor.execute()
   │
   ▼
5. HTTP Sidecar
   ├── POST /execute
   ├── Run code in main container
   └── Return stdout/stderr/files
   │
   ▼
6. Response Processing
   ├── Save state (Python only)
   ├── Store generated files
   └── Destroy pod (pool replenishes)
   │
   ▼
7. Client Response
```

## State Persistence (Python)

Python sessions support state persistence across executions:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Execute   │ ──► │   Capture   │ ──► │    Save     │
│    Code     │     │   State     │     │  to Redis   │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                          ▼
                    cloudpickle + lz4
                    (compressed state)
```

**State Flow:**
1. Before execution: Load state from Redis (or MinIO archive)
2. Execute code with state restoration
3. After execution: Capture and save new state
4. Archive to MinIO after TTL expires

## Configuration

### Pod Pool Settings

```python
# Enable/disable pod pools
POD_POOL_ENABLED=true
POD_POOL_WARMUP_ON_STARTUP=true

# Per-language pool sizes (0 = use Jobs)
POD_POOL_PY=5      # Python: 5 warm pods
POD_POOL_JS=2      # JavaScript: 2 warm pods
POD_POOL_TS=0      # TypeScript: use Jobs
POD_POOL_GO=0      # Go: use Jobs
POD_POOL_JAVA=0    # Java: use Jobs
POD_POOL_RS=0      # Rust: use Jobs
```

### Kubernetes Settings

```python
K8S_NAMESPACE=librecodeinterpreter
K8S_SIDECAR_IMAGE=ghcr.io/.../sidecar:latest
K8S_CPU_LIMIT=1
K8S_MEMORY_LIMIT=512Mi
K8S_CPU_REQUEST=100m
K8S_MEMORY_REQUEST=128Mi
```

## Security Model

### Pod Isolation

Each execution pod is isolated via:

1. **Network Policy**: Deny all egress by default
2. **Security Context**:
   - `runAsNonRoot: true`
   - `runAsUser: 1000`
   - Resource limits enforced
3. **Ephemeral Storage**: Pods destroyed after execution
4. **No Privileged Access**: Standard user containers

### RBAC Requirements

The API deployment needs these Kubernetes permissions:
- `pods`: create, delete, get, list, watch
- `jobs`: create, delete, get, list, watch

## Directory Structure

```
src/
├── api/                    # FastAPI route handlers
│   ├── exec.py            # Code execution endpoint
│   ├── files.py           # File management
│   ├── health.py          # Health checks
│   └── state.py           # State management
│
├── config/                 # Configuration
│   ├── __init__.py        # Settings (Pydantic)
│   ├── languages.py       # Language definitions
│   └── security.py        # Security settings
│
├── models/                 # Pydantic models
│   ├── execution.py       # Execution models
│   ├── session.py         # Session models
│   └── pool.py            # Pool models
│
├── services/               # Business logic
│   ├── execution/         # Execution service
│   │   ├── runner.py      # CodeExecutionRunner
│   │   └── output.py      # Output processing
│   │
│   ├── kubernetes/        # Kubernetes integration
│   │   ├── manager.py     # KubernetesManager
│   │   ├── pool.py        # PodPoolManager
│   │   ├── job_executor.py
│   │   ├── client.py      # K8s client factory
│   │   └── models.py      # PodHandle, etc.
│   │
│   ├── session.py         # SessionService
│   ├── file.py            # FileService
│   ├── state.py           # StateService
│   ├── health.py          # HealthService
│   └── orchestrator.py    # ExecutionOrchestrator
│
├── middleware/             # FastAPI middleware
│   ├── security.py        # Auth, rate limiting
│   └── metrics.py         # Request metrics
│
└── main.py                 # Application entry point

docker/
└── sidecar/               # HTTP sidecar container
    ├── main.py            # FastAPI sidecar server
    ├── Dockerfile
    └── requirements.txt

helm-deployments/
└── librecodeinterpreter/  # Helm chart
    ├── templates/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── serviceaccount.yaml
    │   ├── role.yaml
    │   └── networkpolicy.yaml
    └── values.yaml
```

## Monitoring

### Health Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Basic liveness check |
| `GET /health/ready` | Readiness (all services) |
| `GET /health/kubernetes` | Kubernetes connectivity |
| `GET /health/pool` | Pod pool statistics |

### Metrics

The API exposes metrics for:
- Execution count by language and status
- Execution latency (P50, P95, P99)
- Pool hit/miss ratio
- Active sessions count

## Deployment

### Helm Installation

```bash
helm install librecodeinterpreter ./helm-deployments/librecodeinterpreter \
  --namespace librecodeinterpreter \
  --create-namespace \
  --set api.replicas=2 \
  --set execution.languages.python.poolSize=5
```

### Required Infrastructure

- **Kubernetes 1.24+**: Pod and Job execution
- **Redis 6+**: Session and state storage
- **MinIO/S3**: File storage and state archives
