.PHONY: help env up down clean ps logs restart stop dev test test-all build

# 中文 Windows 下 make 的 recipe 不会继承 shell 里临时设置的编码变量，
# 而 langgraph / python-dotenv 读 .env、langgraph.json 时按系统默认编码（GBK），
# 会报 UnicodeDecodeError。这里给所有 recipe 统一打开 Python UTF-8 模式。
export PYTHONUTF8 := 1
export PYTHONIOENCODING := utf-8

# 可选：只操作某个服务，例如 make up SERVICE=nacos / make logs SERVICE=langfuse-web
SERVICE ?=

help:
	@echo "make env                         create .env from .env.example (never overwrites)"
	@echo "make up                          start all services (first run pulls images)"
	@echo "make up SERVICE=nacos            start one service only"
	@echo "make ps                          show container status"
	@echo "make logs                        follow all logs"
	@echo "make logs SERVICE=nacos          follow one service's logs"
	@echo "make stop SERVICE=milvus         stop one service"
	@echo "make restart SERVICE=litellm     restart one service (after editing litellm-config.yaml)"
	@echo "make down                        stop containers, keep volumes"
	@echo "make clean                       stop containers and delete volumes"
	@echo "make dev                         start Agent on 127.0.0.1:2024"
	@echo "make test                        unit tests (no Docker needed)"
	@echo "make test-all                    all tests (needs MinIO + OpenSandbox)"
	@echo "make build                       build Agent image"

# 从模板生成 .env（已存在则跳过，避免覆盖你填好的 Key）
env:
	@uv run python -c "import pathlib, shutil; s=pathlib.Path('.env.example'); d=pathlib.Path('.env'); print('.env already exists, skipped') if d.exists() else (shutil.copyfile(s, d), print('.env created from .env.example'))"

up:
	docker compose up -d --wait $(SERVICE)

down:
	docker compose down

# 停止并删除数据卷（Milvus / Nacos / Langfuse 数据都会没）
clean:
	docker compose down -v

ps:
	docker compose ps

logs:
	docker compose logs -f --tail=100 $(SERVICE)

stop:
	docker compose stop $(SERVICE)

# 重启某个服务。改了 litellm-config.yaml 后：make restart SERVICE=litellm
restart:
	docker compose restart $(SERVICE)

# Agent 开发服务器（统一已开启 PYTHONUTF8，Windows 也能直接跑）
dev:
	uv run langgraph dev --host 127.0.0.1 --port 2024 --no-browser

# 只跑单元测试，不需要 Docker
test:
	uv run pytest -q tests/units

# 全部测试，需要共享 MinIO + OpenSandbox
test-all:
	uv run pytest -q tests

build:
	uv run langgraph build -t deal-pilot:latest
