# Deal Pilot

一个基于 **LangGraph + Deep Agents** 的企业知识库问答 Agent 工程。

它把 Agent 应用常见的工程环节都串了起来：

- **Agent 编排**：Deep Agents（主 Agent + 子 Agent + 中间件 + Skills）
- **配置治理**：Nacos 3（AgentSpec、Prompt、MCP、配置项）
- **模型网关**：LiteLLM（统一模型入口、按会话粘性路由）
- **可观测**：Langfuse（Trace、Session、Token / 成本、实验与告警 Webhook）
- **沙箱执行**：OpenSandbox（Agent 在隔离容器里跑代码、读写文件）
- **RAG 索引**：飞书文档 → 结构化解析 → 切分 → 向量化 → Milvus
- **对象存储**：MinIO（用户上传文件、Agent 产物、沙箱共享卷）

> 说明：当前 RAG 部分实现的是**文档索引链路**（`feishu_doc_index` 图），Agent 默认工具集里**没有检索工具**。
> 也就是说"文档能进 Milvus"已验证，"Agent 基于 Milvus 回答问题"还需要自己补一个检索工具。详见 [已知限制](#8-已知限制)。

---

## 目录

- [1. 先看这张表：能跑到什么程度](#1-先看这张表能跑到什么程度)
- [2. 准备工作（只做一次）](#2-准备工作只做一次)
- [3. 从零跑通：一步一步照做](#3-从零跑通一步一步照做)
- [4. 服务与端口](#4-服务与端口)
- [5. 配置说明](#5-配置说明)
- [6. Nacos 里需要配置什么](#6-nacos-里需要配置什么)
- [7. 常见问题](#7-常见问题)
- [8. 已知限制](#8-已知限制)
- [9. 停止与清理](#9-停止与清理)
- [10. 目录结构](#10-目录结构)

---

## 1. 先看这张表：能跑到什么程度

这个项目分两层：

- **最小跑通**：不花钱、不需要模型 Key。依赖装好、容器起来、Agent 服务能响应 `/ok`。
- **完整跑通**：在最小跑通的基础上，填模型 Key 和 Nacos 密码，能真正对话。

按下面顺序做，每一步都有明确的成功标志：

| # | 做什么 | 依赖 | 成功标志 | 验证状态 |
|---|--------|------|----------|----------|
| 1 | `uv sync` | uv + Python 3.13.11 | 装好依赖，生成 `.venv` | ✅ 已验证 |
| 2 | `make test` | 无 | `348 passed` | ✅ 已验证 |
| 3 | `make up` | Docker Desktop | 15 个容器 Up | ✅ 已验证 |
| 4 | 配置 LiteLLM 网关 | 上游模型 Key | `/v1/models` 能看到模型 | ⚠️ 当前为空，需在 UI 添加模型 |
| 5 | `make dev` | 上面全部 | `/ok` 返回 `{"ok":true}` | ✅ 已验证 |
| 6 | 真实对话一轮 | 上面全部 + Nacos 密码 | Agent 返回回答 | ⚠️ 需要你填 Key 后验证 |
| 7 | 飞书文档入库 Milvus | 上面全部 + 飞书应用 | Milvus 出现 collection | ⚠️ 未实测 |

> 第一次做，直接从 [第 2 节](#2-准备工作只做一次) 开始，按顺序一条条执行即可。
> 全程使用 **PowerShell**，不要用 CMD。

---

## 2. 准备工作（只做一次）

### 2.1 你需要什么

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10/11（macOS / Linux 也可，命令自行替换） |
| 内存 | **16 GB 以上**（ClickHouse + Milvus + Nacos 比较吃内存） |
| 磁盘 | 预留 **20 GB**（镜像约 8–10 GB，还有数据卷） |
| 网络 | 首次拉镜像需要能访问 Docker Hub 和 `docker.langfuse.com`；国内网络建议先配好代理，见 [Q10](#q10-docker-拉镜像超时--卡住) |
| 虚拟化 | Docker Desktop 需要开启 BIOS 虚拟化和 WSL2 |

### 2.2 安装 Docker Desktop

```powershell
winget install --id Docker.DockerDesktop -e
```

装完**重启电脑**，然后打开 Docker Desktop，等托盘图标变成绿色。

如果提示缺少 WSL2，用管理员 PowerShell 执行：

```powershell
wsl --install
```

然后重启。

验证 Docker 真的在工作（不是只有图标亮着）：

```powershell
docker --version
docker compose version
docker info
```

`docker info` 能输出 `Server Version: ...` 才算成功。

### 2.3 安装 uv

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

或者：

```powershell
winget install --id astral-sh.uv -e
```

装完**关掉当前 PowerShell 再重新打开**，验证：

```powershell
uv --version
```

### 2.4 安装 GNU Make

```powershell
choco install make -y
```

没有 Chocolatey 就用 Scoop：

```powershell
scoop install make
```

验证：

```powershell
make --version
```

> 实在装不上 Make 也不影响运行：`Makefile` 里每个命令都对应一条原始命令，
> 你也可以用 `.\dev.ps1` 启动 Agent。但后面的步骤默认你已经装好 Make。

### 2.5 一次检查全部工具

```powershell
git --version
uv --version
make --version
docker --version
docker compose version
```

四个都输出版本号，再往下走。

---

## 3. 从零跑通：一步一步照做

> 建议按顺序执行。每一步的"成功标志"没出现，就先解决问题，不要跳到下一步。

总进度表（做完一项打个勾）：

| 步骤 | 命令 | 成功标志 |
|------|------|----------|
| 1 | `git clone` | 能看到 `Makefile`、`docker-compose.yml` |
| 2 | `uv sync` | 生成 `.venv` |
| 3 | `make test` | `348 passed` |
| 4 | `make env` | 生成 `.env` |
| 5 | `make up` | `make ps` 显示 15 个容器 |
| 6 | 浏览器设置 Nacos 密码 | 能登录 `localhost:8080` |
| 7 | 在 LiteLLM UI 添加模型 | `/v1/models` 能看到模型 |
| 8 | 编辑 `.env` | 3 个 `OPENAI_*` 和 `NACOS_PASSWORD` 都填好 |
| 9 | `make dev` | 输出 `API: http://127.0.0.1:2024` |
| 10 | 调用 `/ok` | 返回 `{"ok":true}` |
| 11 | 调用 `/runs/wait` | 返回一条 AI 回答 |

### 3.1 第 1 步：获取代码

如果你有仓库地址：

```powershell
git clone <你的仓库地址> deal-pilot
cd deal-pilot
```

> `<你的仓库地址>` 换成这份代码实际托管的地址（GitHub / Gitee 都行）。
> 如果还没推到远程仓库，直接把整个项目文件夹拷给别人也一样，后面步骤完全相同。

如果拿到的是压缩包，解压后进入项目根目录即可，效果一样：

```powershell
cd <解压后的项目目录>
```

确认目录里有这些文件：

```powershell
Get-ChildItem
```

应该能看到：`Makefile`、`docker-compose.yml`、`pyproject.toml`、`src`、`tests`。

### 3.2 第 2 步：安装 Python 依赖

```powershell
uv sync
```

`uv` 会自动读取 `.python-version`（3.13.11），下载对应 Python 并创建 `.venv`。
成功标志：出现 `Installed ... packages`，目录下多了一个 `.venv`。

确认 Python 版本：

```powershell
uv run python -V
```

必须是 `Python 3.13.11`。如果提示版本不匹配，见 [Q3](#q3-uv-sync-报-resolved-to-python-31315-which-is-incompatible-with-31311)。

### 3.3 第 3 步：先跑单元测试

这一步不需要 Docker、不需要任何 Key，用来确认依赖和环境没问题：

```powershell
make test
```

成功标志：

```text
348 passed
```

如果这里就失败，先别往下走，把报错贴出来排查。

### 3.4 第 4 步：生成本地配置 `.env`

```powershell
make env
```

成功标志：

```text
.env created from .env.example
```

> `make env` 只在 `.env` 不存在时创建，**不会覆盖你已经填好的 Key**。
> 如果提示 `.env already exists, skipped`，说明已经有一份了，直接编辑它即可。

现在先不用填全部内容。只需要知道后面会改这两处：

| 变量 | 什么时候填 | 填什么 |
|------|-----------|--------|
| `NACOS_PASSWORD` | 第 6 步设置完 Nacos 密码后 | 你刚设置的密码 |
| `OPENAI_API_KEY` / `OPENAI_BASE_URL` / `OPENAI_DEFAULT_MODEL` | 第 7 步 | 模型服务的地址、Key、模型名 |

`OPEN_SANDBOX_API_KEY` 模板里已经有默认值，本地开发不用改。

### 3.5 第 5 步：启动基础设施

确认 Docker Desktop 已经启动（托盘图标绿色），然后：

```powershell
make up
```

首次执行要拉 15 个镜像，**5–15 分钟很正常**。`make up` 内部会等所有 healthcheck 通过才返回。

成功标志：

```powershell
make ps
```

能看到 **15 行**，带 healthcheck 的服务都是 `(healthy)`：

```text
langfuse-clickhouse   Up (healthy)
langfuse-minio        Up (healthy)
langfuse-postgres     Up (healthy)
langfuse-redis        Up (healthy)
langfuse-web          Up
langfuse-worker       Up
litellm               Up
litellm_postgres      Up (healthy)
litellm_redis         Up (healthy)
milvus                Up (healthy)
milvus-etcd           Up (healthy)
milvus-minio          Up (healthy)
nacos                 Up
opensandbox-server    Up
shared-minio          Up (healthy)
```

快速体检（都返回 `200` 就对了）：

```powershell
(Invoke-WebRequest http://127.0.0.1:9091/healthz -UseBasicParsing).StatusCode      # Milvus
(Invoke-WebRequest http://localhost:8080 -UseBasicParsing).StatusCode               # Nacos
(Invoke-WebRequest http://localhost:3000 -UseBasicParsing).StatusCode               # Langfuse
(Invoke-WebRequest http://localhost:4000/health/liveliness -UseBasicParsing).StatusCode  # LiteLLM
```

> OpenSandbox 的 `http://127.0.0.1:8090` 返回 `401` 是正常的，它要带 Key 才能访问。
>
> 如果卡在拉镜像、报超时，见 [Q10](#q10-docker-拉镜像超时--卡住)。

### 3.6 第 6 步：第一次登录 Nacos，设置密码

1. 浏览器打开 <http://localhost:8080>
2. 首次访问会让你**初始化管理员密码**，用户名是 `nacos`
3. 设置一个你能记住的密码
4. 把密码写进 `.env`：

```dotenv
NACOS_USERNAME=nacos
NACOS_PASSWORD=你刚设置的密码
```

成功标志：能正常进入 Nacos 控制台。

> 如果打开后没有让你初始化，而是直接显示登录页，先试默认的 `nacos` / `nacos`。
>
> `.env` 改完后，如果 Agent 已经在运行，需要 `Ctrl+C` 停掉再重新 `make dev`。

### 3.7 第 7 步：配置 LiteLLM 网关（添加模型）

> 本项目默认走 LiteLLM 网关（`.env` 里 `OPENAI_BASE_URL=http://127.0.0.1:4000/v1`）。
> 网关刚启动时是空的，一个模型都没有，所以**这一步不能跳过**。

先确认网关本身是通的：

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw
```

刚启动时返回空列表，这是正常的：

```json
{"data":[],"object":"list"}
```

现在去 UI 里加模型：

1. 打开 <http://localhost:4000/ui>，用 `admin` / `123456` 登录
2. 进入 `Models` → `Add Model`
3. 填四样东西（不同版本字段名略有差异，认准含义即可）：
   - **Public Model Name / Model Name**：网关对外的模型名，例如 `qwen-plus`，后面 `.env` 的 `OPENAI_DEFAULT_MODEL` 就填它
   - **Provider**：上游服务商；没有对应选项就选 `OpenAI-Compatible`
   - **API Base / Base URL**：上游服务地址，例如 `https://dashscope.aliyuncs.com/compatible-mode/v1`
   - **API Key**：上游厂商的 Key（**不是**网关的 master key）
4. 保存

回到终端再查一次：

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
(Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw).data.id
```

成功标志：输出你刚添加的模型名，例如：

```text
qwen-plus
```

> 这里看不到模型，就不要往下走。先回 UI 确认模型保存成功、上游 Key 没填错。
>
> UI 里添加的模型保存在 LiteLLM 自己的 Postgres 数据卷里，`make down` 不会丢；
> 只有 `make clean` 删除数据卷后才会清空。

### 3.8 第 8 步：把网关配置写进 `.env`

编辑 `.env`，填这四项：

```dotenv
OPENAI_BASE_URL=http://127.0.0.1:4000/v1
OPENAI_API_KEY=sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9
OPENAI_DEFAULT_MODEL=qwen-plus
NACOS_PASSWORD=第 6 步设置的 Nacos 密码
```

说明：

- `OPENAI_BASE_URL` 填**网关地址**，不是上游地址
- `OPENAI_API_KEY` 填 LiteLLM 的 **master key**（就是上面这一长串），不是上游厂商的 Key
- `OPENAI_DEFAULT_MODEL` 必须和 UI 里的 **Public Model Name** 一模一样
- master key 以 `docker-compose.yml` 里的 `LITELLM_MASTER_KEY` 为准；改过 compose 就要跟着改

检查四项都不是空：

```powershell
Select-String -Path .env -Pattern '^OPENAI_|^NACOS_PASSWORD'
```

最后**先不启动 Agent**，直接通过网关发一条消息，确认"网关 → 上游模型"整条链路是通的：

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }

$body = @{
  model = "qwen-plus"
  messages = @(@{ role = "user"; content = "你好" })
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri http://127.0.0.1:4000/v1/chat/completions `
  -Method Post -Headers $gw -ContentType "application/json" -Body $body
```

成功标志：返回里有 `choices[0].message.content`，内容是一句正常回答。

> 这一步失败就说明网关没配好，先解决网关，不要急着启动 Agent。
> 常见原因：模型名和 UI 里不一致、上游 Key 错、上游地址多了或少了 `/v1`。

### 3.9 第 9 步：启动 Agent

```powershell
make dev
```

`Makefile` 已经统一设置了 `PYTHONUTF8=1`，中文 Windows 下不会再报 GBK 解码错误。

成功标志（第一次启动约 20–30 秒）：

```text
- API: http://127.0.0.1:2024
- Studio UI: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024
- API Docs: http://127.0.0.1:2024/docs
```

**这个终端不要关**，Agent 就运行在这里。后面的验证另开一个 PowerShell 窗口。

如果启动日志里出现 `Graph import exceeded the expected startup time`，只是启动慢，不影响使用。

### 3.10 第 10 步：验证 Agent 服务

另开一个 PowerShell 窗口，先做健康检查（不需要 Token）：

```powershell
(Invoke-WebRequest http://127.0.0.1:2024/ok -UseBasicParsing).Content
```

成功标志：

```json
{"ok":true}
```

再看图有没有注册（需要 Token）：

```powershell
$h = @{ Authorization = "Bearer admin" }
(Invoke-RestMethod -Uri http://127.0.0.1:2024/assistants/search `
  -Method Post -Headers $h -ContentType "application/json" -Body '{}').graph_id
```

成功标志：输出三张图

```text
feishu_doc_index
delete_old_trace
main_agent
```

> 可用 Token：`admin`、`user_1`、`user_2`、`test_user`（见 `src/deal_pilot/utils/mock_user.py`）。
> 这是 Mock 鉴权，只适合本地开发。

### 3.11 第 11 步：发出第一条真实消息

在刚才那个新窗口里执行：

```powershell
$h = @{ Authorization = "Bearer admin" }

$body = @{
  assistant_id = "main_agent"
  input = @{
    messages = @(
      @{ role = "user"; content = "你好，用一句话介绍你自己" }
    )
  }
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Uri http://127.0.0.1:2024/runs/wait `
  -Method Post -Headers $h -ContentType "application/json" -Body $body
```

成功标志：返回 JSON 里有一条 `type = "ai"` 的消息，`content` 是模型回答，且**没有** `__error__` 字段。

第一次调用可能要等 10–60 秒（要连 Nacos、连模型），属正常。

如果失败，对照这张表：

| 返回 / 现象 | 原因 | 怎么修 |
|-------------|------|--------|
| `{"__error__":{"error":"ConnectError"...}}` | Nacos 没起来 / 连不上 | `make up SERVICE=nacos`，确认 `NACOS_SERVER_ADDRESS` |
| `{"__error__":{"error":"UnsupportedProtocol"...}}` | `.env` 没生效，地址是空的 | 检查 `.env` 是否存在、是否重启过 `make dev` |
| `401 Unauthorized` | 没带 Token | 请求头加 `Authorization: Bearer admin` |
| `model not found` / `404` | 模型名不对 | `OPENAI_DEFAULT_MODEL` 必须和服务商一致 |
| `Incorrect API key` / `401` | Key 不对 | 直连填服务商 Key；走 LiteLLM 填 master key |
| `400 ... enable_thinking` | 该模型不支持思考参数 | 见 [Q11](#q11-模型报-400-unknown-parameter-enable_thinking) |

### 3.12 第 12 步（可选）：在 Langfuse 里看到 Trace

不做这一步也能正常对话，只是没有链路追踪。

1. 打开 <http://localhost:3000>，注册账号并创建 Organization / Project
2. 进入项目 → `Settings` → `API Keys` → 创建一个 Key
3. 把 Public / Secret Key 填进 `.env`：

```dotenv
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_BASE_URL=http://localhost:3000
```

4. `Ctrl+C` 停掉 `make dev`，重新启动
5. 再发一次消息，回到 Langfuse 的 `Tracing` 页面，能看到刚才那一轮调用

### 3.13 第 13 步（可选）：在 Nacos 里建 AgentSpec

不做这一步，Agent 就是一个"没有 system prompt、没有工具"的裸模型，仍然能回答，
但不会用工具、也没有人设。想要完整形态，按 [第 6 节](#6-nacos-里需要配置什么) 建一个 `main_agent`。

### 3.14 到这里检查一遍

全部打勾就说明**完整跑通**了：

- [ ] `uv run python -V` 输出 `Python 3.13.11`
- [ ] `make test` 输出 `348 passed`
- [ ] `make ps` 显示 15 个容器，该 healthy 的都 healthy
- [ ] Nacos 能登录，`.env` 里的 `NACOS_PASSWORD` 和页面一致
- [ ] `/v1/models` 能看到你在 LiteLLM 里添加的模型
- [ ] 直接调 `/v1/chat/completions` 能拿到上游模型的回答
- [ ] `make dev` 输出 `API: http://127.0.0.1:2024`
- [ ] `GET /ok` 返回 `{"ok":true}`
- [ ] `assistants/search` 能看到 `main_agent`、`delete_old_trace`、`feishu_doc_index`
- [ ] `POST /runs/wait` 能返回一条正常回答
- [ ] （可选）Langfuse 能看到 Trace

---

## 4. 服务与端口

| 服务 | 地址 | 账号 / 说明 |
|------|------|-------------|
| **Agent API** | <http://127.0.0.1:2024> | `Authorization: Bearer admin` |
| API 文档 | <http://127.0.0.1:2024/docs> | 自动生成 |
| LangGraph Studio | `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024` | 自定义鉴权，Studio 可能要求填 Token |
| **Langfuse** | <http://localhost:3000> | 首次访问自己注册账号 |
| **LiteLLM** | <http://localhost:4000/ui> | `admin` / `123456` |
| LiteLLM API | <http://localhost:4000/v1> | Key 用 compose 里的 `LITELLM_MASTER_KEY` |
| **Nacos** | <http://localhost:8080> | 首次访问设置密码，用户名 `nacos` |
| Nacos API | <http://localhost:8848> | 应用代码走这个端口 |
| OpenSandbox | <http://127.0.0.1:8090> | Key 用 `.env` 的 `OPEN_SANDBOX_API_KEY` |
| Milvus | `127.0.0.1:19530`（gRPC） | 健康检查 <http://127.0.0.1:9091/healthz> |
| 共享 MinIO | API `localhost:9002`，控制台 <http://localhost:9003> | `root` / `12345678` |
| Langfuse MinIO | API `localhost:9000`，控制台 <http://localhost:9001> | `root` / `12345678` |
| Milvus MinIO | API `localhost:19000`，控制台 <http://localhost:19001> | `minioadmin` / `minioadmin` |

快速体检（Agent 那行需要 `make dev` 已启动）：

```powershell
(Invoke-WebRequest http://127.0.0.1:2024/ok -UseBasicParsing).StatusCode            # Agent
(Invoke-WebRequest http://127.0.0.1:9091/healthz -UseBasicParsing).StatusCode        # Milvus
(Invoke-WebRequest http://127.0.0.1:8080 -UseBasicParsing).StatusCode                # Nacos
(Invoke-WebRequest http://127.0.0.1:3000 -UseBasicParsing).StatusCode                # Langfuse
(Invoke-WebRequest http://127.0.0.1:4000/health/liveliness -UseBasicParsing).StatusCode  # LiteLLM
```

---

## 5. 配置说明

所有配置都在 `.env`，由 `pydantic-settings` 读取（`deal_pilot/config/base_settings.py`）。

### 5.1 必填

| 变量 | 作用 | 说明 |
|------|------|------|
| `OPENAI_API_KEY` | 模型 Key | 默认填 LiteLLM 的 `LITELLM_MASTER_KEY`；直连模式填服务商 Key |
| `OPENAI_BASE_URL` | 模型地址 | 默认 `http://127.0.0.1:4000/v1`；直连模式填服务商地址 |
| `OPENAI_DEFAULT_MODEL` | 默认模型名 | 必须和实际模型名一致 |
| `NACOS_SERVER_ADDRESS` | Nacos 地址 | `http://localhost:8848` |
| `NACOS_USERNAME` / `NACOS_PASSWORD` | Nacos 账号 | 首次登录时设置 |
| `NACOS_NAMESPACE_ID` | 命名空间 | 默认 `public` |

### 5.2 按需填

| 变量 | 不填的后果 |
|------|-----------|
| `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` | 没有 Trace，Langfuse 后台是空的 |
| `TAVILY_API_KEY` | `web_search` 工具调用失败 |
| `FEISHU_APP_ID` / `FEISHU_APP_SECRET` | `feishu_doc_index` 图跑不了 |
| `OPEN_SANDBOX_API_KEY` | `make up` 直接报错退出（compose 要求必填）。它是自建服务的访问口令，自己定随机串即可，不是官方发放的 |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | 文件上传、沙箱共享卷不可用 |

### 5.3 模型网关

**默认：走 LiteLLM**（和 [3.7](#37-第-7-步配置-litellm-网关添加模型) 对应）

1. 打开 <http://localhost:4000/ui>，用 `admin` / `123456` 登录
2. `Models` → `Add Model`，填上游 Provider、公开模型名、上游地址、上游 Key
3. 先确认 `GET /v1/models` 能看到刚添加的模型
4. `.env` 里：

```dotenv
OPENAI_BASE_URL=http://127.0.0.1:4000/v1
OPENAI_API_KEY=<docker-compose.yml 里的 LITELLM_MASTER_KEY>
OPENAI_DEFAULT_MODEL=<UI 里的 Public Model Name>
```

好处：模型切换、限流、花销统计、Langfuse 追踪都在一起，也是本项目的默认设计。

**可选：直连 OpenAI 兼容服务（跳过 3.7）**

```dotenv
OPENAI_BASE_URL=https://your-endpoint/v1
OPENAI_API_KEY=sk-xxx
OPENAI_DEFAULT_MODEL=your-model
```

不用配 LiteLLM，但 `make up` 仍会把它拉起来（不影响使用）。
面试演示建议还是走网关，能体现项目里的模型治理设计。

---

## 6. Nacos 里需要配置什么

Agent 启动时会从 Nacos 拉三类东西，**没有就退化，拉不到就报错**。

### 6.1 AgentSpec（决定 Agent 的人设、工具、模型）

代码位置：`src/deal_pilot/config/nacos/nacos_agent_spec.py`

```text
GET /nacos/v3/client/ai/agentspecs?namespaceId=public&name=main_agent&label=production
```

在 Nacos 控制台 → **AI Registry** → Agent 管理里创建：

- 名称：`main_agent`
- 标签：`production`（代码里写死了 `label=production`）
- 命名空间：`public`
- 内容（JSON）：

```json
{
  "description": "企业知识库问答助手",
  "model": {
    "name": "your-model",
    "thinking": true,
    "temperature": 0.7
  },
  "tools": ["get_current_time", "web_search", "fetch_url"],
  "mcps": {},
  "subagents": [],
  "skills": []
}
```

- `instruction_main_agent/AGENTS__MD` 这份资源会作为 system prompt
- `tools` 只能填代码里注册过的名字，见 `src/deal_pilot/tools/__init__.py`：
  `fetch_url`、`web_search`、`get_current_time`、`ask_user_question`、`deploy`
- `subagents` 目前只支持 `web_agent`（见 `agent_factory.py` 的 `_AGENT_FACTORIES`）

**没配 AgentSpec 会怎样**：Nacos 返回 `code != 0` 时，代码返回 `AgentSpec(name="main_agent")`，
即空 prompt、空工具、模型取 `OPENAI_DEFAULT_MODEL`。还能对话，但只是一个裸模型。

> 如果模型不支持 `enable_thinking` 参数，把上面的 `"thinking": true` 改成 `"thinking": false`，
> 否则可能报 400，见 [Q11](#q11-模型报-400-unknown-parameter-enable_thinking)。

### 6.2 两个业务配置

代码位置：`src/deal_pilot/config/nacos/nacos_config.py`

| dataId | group | 用在哪 |
|--------|-------|--------|
| `sandbox_config` | `deal_pilot` | OpenSandbox 沙箱镜像、资源限制、挂载 |
| `rag_config` | `deal_pilot` | 向量库、embedding 模型 |

格式是 YAML。这两份配置**仓库里没有样例**，需要用沙箱/索引功能时按 `nacos_schemas.py` 里的
`OpenSandboxConfig` 等模型自己建。不建的话代码会返回空配置，普通对话不受影响。

### 6.3 改完要不要重启

`NACOS_TTL=5` 表示缓存 5 秒，改了 Nacos 里的配置等几秒就生效，不用重启 Agent。

但改了 **`.env`** 必须重启 `make dev`（配置在进程启动时读取）。

---

## 7. 常见问题

### Q1. `langgraph dev` 报 `UnicodeDecodeError: 'gbk' codec can't decode byte 0x94` / `0xbf`

中文版 Windows 的系统默认编码是 GBK，而 `langgraph-api` 和 `python-dotenv` 读文件时没显式指定 UTF-8：

- `byte 0x94`：读的是 `langgraph.json`（UTF-8 JSON）
- `byte 0xbf`：读的是 `.env`（里面有中文注释）

**用 `make dev` 不会遇到这个问题**：`Makefile` 里已经给所有命令统一设置了 `PYTHONUTF8=1`。
如果绕过 make 手动运行，需要先设置：

```powershell
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
uv run langgraph dev --host 127.0.0.1 --port 2024 --no-browser
```

或者直接用 `.\dev.ps1`（脚本里做了同样的事）。

### Q2. 启动日志里出现 `UnicodeDecodeError` / `--- Logging error ---`

用 `make dev` / `.\dev.ps1` 启动时一般不会出现。如果直接 `uv run langgraph dev` 且没设
`PYTHONUTF8`，会看到一串 GBK 编解码错误。**只要最后能看到 `API: http://127.0.0.1:2024`，
访问 `/ok` 返回 `{"ok":true}`，服务就是正常的**，那些是从子进程重载时打出来的日志噪音。

要彻底消掉就按 Q1 设置 `PYTHONUTF8`，或者直接用 `make dev`。

### Q3. `uv sync` 报 `resolved to Python 3.13.15, which is incompatible with ==3.13.11`

`.python-version` 和 `pyproject.toml` 对不上：

```powershell
uv python pin 3.13.11
uv python install 3.13.11
uv sync
```

### Q4. `docker compose` 报 `required variable OPEN_SANDBOX_API_KEY is missing a value`

先看 `.env` 是不是空文件（0 字节）：

```powershell
Get-Item .env | Select-Object Name, Length     # Length 必须大于 0
Get-Content .env | Measure-Object -Line         # 应该有几行
```

如果是空的，重新生成一份：

```powershell
Copy-Item .env.example .env -Force
```

`OPEN_SANDBOX_API_KEY` 没有"官方发放"这回事，**它是自建 OpenSandbox 服务的访问口令，自己随便定一个随机串就行**。
compose 的服务端和 `.env` 里的应用代码读的是同一个变量，所以天然一致：

```powershell
# 需要换一个的话
-join ((1..40) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
```

改完执行 `docker compose config --quiet`，没有任何输出且退出码为 0，就说明变量齐了。

### Q5. 调用 Agent 报 `httpx.ConnectError` / `UnsupportedProtocol`

两种原因：

- `NACOS_SERVER_ADDRESS` 是空的 → 没建 `.env`
- Nacos 没启动 → `make up SERVICE=nacos`

还有一种常见情况：Nacos 密码填错了。`docker compose ps` 里 nacos 是 Up，但登录接口返回
401/403，也会表现为 Agent 调用失败。重新检查 `.env` 里的 `NACOS_PASSWORD`，改完重启 `make dev`。

Agent 启动第一件事就是拿 Nacos 的 access token，拿不到直接抛异常。

### Q6. 调用 Agent 报 `401 Unauthorized`

接口要带 Token：

```text
Authorization: Bearer admin
```

可用 Token：`admin`、`user_1`、`user_2`、`test_user`（见 `src/deal_pilot/utils/mock_user.py`）。

### Q7. 模型报 `model not found` / `401`

- **先检查网关里到底有没有模型**：

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
(Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw).data.id
```

返回空就说明模型还没加，回到 [3.7](#37-第-7-步配置-litellm-网关添加模型)。

- 走 LiteLLM：模型名要和 `OPENAI_DEFAULT_MODEL` 完全一致（= UI 里的 Public Model Name）
- `OPENAI_API_KEY` 用 LiteLLM 的 master key，不是上游厂商的 key
- 直连模式：确认 `OPENAI_BASE_URL` 以 `/v1` 结尾，模型名和服务商文档一致

### Q8. `make up` 卡住 / OOM

先只拉起需要的：

```powershell
make up SERVICE=nacos
make up SERVICE=milvus
```

Docker Desktop 里把内存调到 **8 GB 以上**（Settings → Resources）。
Milvus 首次启动有 90 秒的 `start_period`，慢一点是正常的。

### Q9. 端口被占用

报错里会写哪个端口。查占用：

```powershell
Get-NetTCPConnection -LocalPort 2024 -State Listen | Select-Object OwningProcess
```

把占用的进程结束掉，或者换端口：

```powershell
.\dev.ps1 -Port 2025
```

### Q10. Docker 拉镜像超时 / 卡住

典型报错：

```text
failed to do request: ... dial tcp ... i/o timeout
```

国内网络访问 Docker Hub 和 `docker.langfuse.com` 经常超时。处理顺序：

1. 确认电脑上的代理软件已经开启（例如 Clash），记下它的 **HTTP 代理端口**（常见 `7897`）
2. Docker Desktop → `Settings` → `Resources` → `Proxies` → 勾选手动代理，填 `http://127.0.0.1:7897`
3. `Apply & restart`，然后重新执行：

```powershell
make up
```

4. 还是不行就单独重试某个镜像：

```powershell
docker pull docker.langfuse.com/langfuse/langfuse:4
```

> 公司网络如果强制走代理，也可以在 PowerShell 里临时设置 `HTTP_PROXY` / `HTTPS_PROXY` 再执行 `docker compose`。

### Q11. 模型报 `400 unknown parameter enable_thinking`

项目默认会给模型传 `extra_body={"enable_thinking": true}`（见 `src/deal_pilot/utils/create_model.py`），
部分模型（例如一些 OpenAI 模型）不认这个参数。

两种处理：

1. 换成支持该参数的模型（通义千问 qwen3 系列一般支持）
2. 在 Nacos 的 `main_agent` AgentSpec 里把 `model.thinking` 设为 `false`：

```json
"model": {
  "name": "your-model",
  "thinking": false
}
```

改完等 5 秒（`NACOS_TTL=5`）再发一次消息。

---

## 8. 已知限制

诚实列一下，别被 README 的架构图骗了：

1. **RAG 只有索引侧**。`feishu_doc_index` 图能完成"飞书文档 → 解析 → 切分 → 向量化 → 写 Milvus"，
   但 Agent 的工具集里没有 `search_documents` 之类的检索工具，问答闭环需要自己补。
2. **Nacos 配置没有开箱样例**。`sandbox_config`、`rag_config`、`main_agent` 的 AgentSpec 都要自己建。
3. **没有评测数据集**。`src/deal_pilot/benchmarks` 有评测代码，但没有配套的 dataset 文件。
4. **鉴权是 Mock 的**。`mock_user.py` 里四个写死的用户，只适合本地开发。
5. **中文 Windows 要手动设 UTF-8**，见 Q1；用 `make dev` 已经自动处理。
6. **前 4 步（依赖、测试、容器、Agent 服务）已在本机验证**。真实对话和飞书入库
   还需要有效的模型 Key / Nacos 密码 / 飞书应用，按第 3 节的流程自己走一遍。

---

## 9. 停止与清理

```powershell
# 停止 Agent：在运行 make dev 的终端按 Ctrl+C

# 停止容器，保留数据
make down

# 停止并删除所有数据卷（Milvus / Nacos / Langfuse 数据全没）
make clean

# 只停某个服务
make stop SERVICE=milvus

# 看日志
make logs SERVICE=nacos
make logs SERVICE=langfuse-web
```

---

## 10. 目录结构

```text
deal-pilot/
├── src/deal_pilot/
│   ├── agents/              # Agent 工厂：main_agent、web_agent
│   ├── app/                 # 自定义 FastAPI 路由（Langfuse 告警 / 实验 Webhook）
│   ├── backends/            # Deep Agents 的沙箱后端
│   ├── benchmarks/          # 评测脚本与打分器
│   ├── config/              # pydantic-settings 配置
│   │   └── nacos/           # AgentSpec / Prompt / MCP / 配置中心客户端
│   ├── feishu/              # 飞书开放平台 API 封装
│   ├── graphs/              # 独立图：delete_old_trace、feishu_doc_index
│   ├── middlewares/         # Agent 中间件（轮次摘要）
│   ├── rag/                 # 文档解析 / 切分 / embedding / Milvus store
│   ├── security/            # LangGraph 鉴权
│   ├── tools/               # Agent 工具：web、time、deploy、ask_user
│   └── utils/               # 模型构造、Trace、沙箱、MinIO 等
├── tests/
│   ├── units/               # 单元测试，348 条，不需要外部依赖
│   └── intergrations/       # 集成测试，需要 MinIO / OpenSandbox
├── docker/
│   ├── nacos/               # Nacos 插件状态
│   └── sandbox/             # 沙箱镜像 Dockerfile
├── docker-compose.yml       # 15 个服务
├── langgraph.json           # 图入口与鉴权配置
├── litellm-config.yaml      # LiteLLM 路由配置
├── opensandbox_config.toml  # OpenSandbox 服务端配置
├── pyproject.toml
├── uv.lock
├── .env.example             # 环境变量模板
├── dev.ps1                  # 没有 make 时的 Windows 启动脚本
└── Makefile                 # 常用命令：make env / up / dev / test / down ...
```

---

## 附：命令速查

| 命令 | 作用 |
|------|------|
| `make help` | 列出所有命令 |
| `make env` | 从 `.env.example` 生成 `.env`（已存在则跳过） |
| `make up` | 启动全部容器 |
| `make up SERVICE=nacos` | 只启动某个服务 |
| `make ps` | 查看容器状态 |
| `make logs` / `make logs SERVICE=nacos` | 查看日志 |
| `make stop SERVICE=milvus` | 停止指定服务 |
| `make down` | 停止容器，保留数据 |
| `make clean` | 停止并删除数据卷 |
| `make dev` | 启动 Agent（`127.0.0.1:2024`） |
| `make test` | 单元测试（348 条，不需要 Docker） |
| `make test-all` | 全部测试（需要 MinIO + OpenSandbox） |
| `make build` | 构建 Agent 镜像 |

### 复制即用的验收脚本

```powershell
# 1. 环境
uv run python -V                       # Python 3.13.11
make test                              # 348 passed

# 2. 容器
make ps                                # 15 行，该 healthy 的都 healthy

# 3. 网关（应该能看到你添加的模型）
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
(Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw).data.id

# 4. Agent（另开终端先执行 make dev）
(Invoke-WebRequest http://127.0.0.1:2024/ok -UseBasicParsing).Content   # {"ok":true}

$h = @{ Authorization = "Bearer admin" }
(Invoke-RestMethod -Uri http://127.0.0.1:2024/assistants/search `
  -Method Post -Headers $h -ContentType "application/json" -Body '{}').graph_id
# feishu_doc_index / delete_old_trace / main_agent

# 5. 真实对话
$body = @{
  assistant_id = "main_agent"
  input = @{ messages = @(@{ role = "user"; content = "你好" }) }
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Uri http://127.0.0.1:2024/runs/wait `
  -Method Post -Headers $h -ContentType "application/json" -Body $body
```
