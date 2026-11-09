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

- [1. 跑通之后你能做什么](#1-跑通之后你能做什么)
- [2. 开始前的机器要求](#2-开始前的机器要求)
- [3. 一步步跑通](#3-一步步跑通)
- [4. 服务与端口](#4-服务与端口)
- [5. 配置说明](#5-配置说明)
- [6. Nacos 里需要配置什么](#6-nacos-里需要配置什么)
- [7. 常见问题](#7-常见问题)
- [8. 已知限制](#8-已知限制)
- [9. 停止与清理](#9-停止与清理)
- [10. 目录结构](#10-目录结构)

---

## 1. 跑通之后你能做什么

这个项目分两层，建议按顺序来：

| 阶段 | 需要什么 | 跑通后你能做什么 |
|------|----------|------------------|
| **最小跑通** | 不需要模型 Key，不花钱 | 15 个基础设施容器全部在线，Agent 服务能响应 `/ok`，能打开 Nacos / Langfuse / LiteLLM 后台 |
| **完整跑通** | 一个模型 Key + Nacos 密码 | 能真正和 Agent 对话，请求走 LiteLLM 网关，Agent 配置从 Nacos 下发 |

> 下面从**安装环境**开始，一条线走到底。全程使用 **PowerShell**，不要用 CMD。
> 每一步都写了「完成标志」和「完成这一步后你能做什么」，没出现完成标志就不要跳到下一步。

---

## 2. 开始前的机器要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10/11（macOS / Linux 也可，命令自行替换） |
| 内存 | **16 GB 以上**（ClickHouse + Milvus + Nacos 比较吃内存） |
| 磁盘 | 预留 **20 GB**（镜像 8–10 GB，还有数据卷） |
| 网络 | 首次拉镜像要能访问 Docker Hub 和 `docker.langfuse.com`；国内网络先配代理，见 [Q10](#q10-docker-拉镜像超时--卡住) |
| 虚拟化 | Docker Desktop 需要开启 BIOS 虚拟化和 WSL2 |

---

## 3. 一步步跑通

> 顺序不要跳。每一步的「完成标志」出现之后，再做下一步。

### 3.1 安装 Docker Desktop

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

完成标志：`docker info` 能输出 `Server Version: ...`。

> ✅ **完成这一步后**：你可以在本机启动容器。后面 Nacos、LiteLLM、Milvus、Langfuse 全都靠它。

### 3.2 安装 uv（Python 环境管理）

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

或者：

```powershell
winget install --id astral-sh.uv -e
```

装完**关掉当前 PowerShell 再重新打开**。

完成标志：

```powershell
uv --version
```

> ✅ **完成这一步后**：你能用 `uv` 自动安装本项目指定的 Python 3.13.11 和全部依赖，不用手动配 Python 环境。

### 3.3 安装 GNU Make

```powershell
choco install make -y
```

没有 Chocolatey 就用 Scoop：

```powershell
scoop install make
```

完成标志：

```powershell
make --version
```

> 实在装不上 Make 也不影响运行：`Makefile` 里每个命令都对应一条原始命令，
> 也可以用 `.\dev.ps1` 启动 Agent。但后面的步骤默认你已经装好 Make。

> ✅ **完成这一步后**：后面所有操作都能用 `make xxx` 一条命令完成，不用记长命令。

### 3.4 检查工具是否齐全

```powershell
git --version
uv --version
make --version
docker --version
docker compose version
```

完成标志：五个命令都输出版本号。

> ✅ **完成这一步后**：环境准备结束，可以开始拿代码了。

### 3.5 获取代码

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

完成标志：能看到 `Makefile`、`docker-compose.yml`、`pyproject.toml`、`src`、`tests`。

> ✅ **完成这一步后**：你本地有一份完整项目，后面所有命令都在这个目录里执行。

### 3.6 安装 Python 依赖

```powershell
uv sync
```

`uv` 会自动读取 `.python-version`（3.13.11），下载对应 Python 并创建 `.venv`。

完成标志：出现 `Installed ... packages`，目录下多了一个 `.venv`。

确认版本：

```powershell
uv run python -V
```

必须是 `Python 3.13.11`。版本不匹配见 [Q3](#q3-uv-sync-报-resolved-to-python-31315-which-is-incompatible-with-31311)。

> ✅ **完成这一步后**：Python、依赖、虚拟环境都就位，可以运行和测试项目代码了。

### 3.7 先跑单元测试

这一步不需要 Docker、不需要任何 Key，用来确认依赖和环境没问题：

```powershell
make test
```

完成标志：

```text
348 passed
```

如果这里就失败，先别往下走，把报错贴出来排查。

> ✅ **完成这一步后**：你确认了 Python 环境是好的。后面再出问题，可以直接排除「依赖装坏了」这种可能。

### 3.8 生成本地配置 `.env`

```powershell
make env
```

完成标志：

```text
.env created from .env.example
```

> `make env` 只在 `.env` 不存在时创建，**不会覆盖你已经填好的 Key**。
> 如果提示 `.env already exists, skipped`，说明已经有一份了，直接编辑它即可。

现在先不用填全部内容，后面会改这几处：

| 变量 | 什么时候填 | 填什么 |
|------|-----------|--------|
| `OPEN_SANDBOX_API_KEY` | 不用改 | 模板里已有本地默认值 |
| `NACOS_PASSWORD` | 3.10 设置完 Nacos 密码后 | 你刚设置的密码 |
| `DASHSCOPE_API_KEY` 等 | 3.11 配置网关时 | 上游模型的 Key |
| `OPENAI_API_KEY` / `OPENAI_BASE_URL` / `OPENAI_DEFAULT_MODEL` | 3.12 | 网关的 master key、地址、模型名 |

> ✅ **完成这一步后**：你有一份可编辑的配置文件。下一步启动容器时，compose 就会读它。

### 3.9 启动基础设施

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

> ✅ **完成这一步后**：15 个基础设施容器全部在线，Nacos、LiteLLM、Milvus、Langfuse、MinIO 的后台都能打开。

### 3.10 第一次登录 Nacos，设置密码

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

> ✅ **完成这一步后**：Agent 启动时能登录 Nacos，拿到 AgentSpec / Prompt / MCP 配置。

### 3.11 配置 LiteLLM 网关（添加模型）

> 本项目默认走 LiteLLM 网关（`.env` 里 `OPENAI_BASE_URL=http://127.0.0.1:4000/v1`）。
> 网关刚启动时是空的，一个模型都没有，所以**这一步不能跳过**。

#### 3.11.1 四个"名字 / 钥匙"别搞混

网关配置最容易错的地方，是把下面这几样东西搞混。先看表：

| 名称 | 是什么 | 在哪设置 / 查看 | 填到哪 |
|------|--------|------------------|--------|
| **master key** | 网关的 **root 管理凭证**，`sk-` 开头 | `docker-compose.yml` → `LITELLM_MASTER_KEY`（**不是**在 UI 里创建） | `.env` 的 `OPENAI_API_KEY`（本项目默认做法） |
| **子 Key**（Virtual Key） | 网关的**普通调用凭证**，可限额、限模型、可吊销 | LiteLLM UI → `Virtual Keys` / `Keys` → `Create Key` | `.env` 的 `OPENAI_API_KEY`（二选一，生产推荐） |
| **LiteLLM UI 账号** | 登录后台用的用户名 / 密码 | `docker-compose.yml` → `UI_USERNAME` / `UI_PASSWORD` | 只在浏览器登录用，**不是** API Key |
| **上游厂商 Key** | 阿里云 / DeepSeek / OpenAI 发给你的 Key | 各厂商控制台 | `.env` 的 `DASHSCOPE_API_KEY` 等，再被 `litellm-config.yaml` 引用 |
| **公开模型名**（`model_name`） | 网关对外的模型名字 | `litellm-config.yaml` 的 `model_name` 或 UI | `.env` 的 `OPENAI_DEFAULT_MODEL` |

一句话：

- **master key 确实是访问网关的凭证**，但它的位置在 `docker-compose.yml`，不是 UI。
- **UI 里 `Create Key` 创建的是子 Key**，不是 master key。子 Key 也能访问网关，只是权限可以收窄。
- **`admin` / `123456` 只是登录后台的账号密码**，不能拿来当 API Key 用。

请求链路：

```text
Agent（.env: OPENAI_BASE_URL + OPENAI_API_KEY = master key 或子 Key）
   │
   │  POST /v1/chat/completions   model=<公开模型名>
   ▼
LiteLLM 网关 http://127.0.0.1:4000
   │  用 litellm_params 里的 api_base + api_key
   ▼
上游模型（阿里云百炼 / DeepSeek / OpenAI / 本地 Ollama ...）
```

#### 3.11.2 master key 从哪来（不在 UI 里创建）

本项目的 master key 直接写在 `docker-compose.yml` 的 litellm 服务里：

```yaml
litellm:
  environment:
    LITELLM_MASTER_KEY: "sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9"
```

查看当前值：

```powershell
Select-String -Path docker-compose.yml -Pattern 'LITELLM_MASTER_KEY'
```

验证它能不能用：

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
(Invoke-WebRequest http://127.0.0.1:4000/v1/models -Headers $gw -UseBasicParsing).StatusCode
```

- 返回 `200`：key 对，能访问网关
- 返回 `401`：key 不对，重新从 `docker-compose.yml` 复制

几个注意点：

1. **master key 必须以 `sk-` 开头**，这是 LiteLLM 的格式要求
2. **不要拿上游厂商的 Key 当 master key**，两者完全不是一个东西
3. **改 master key 要两处同步**：`docker-compose.yml` 和 `.env` 的 `OPENAI_API_KEY`，然后 `make restart SERVICE=litellm`
4. 本地开发为了方便才把 master key 写在 compose 里；**真实生产环境**应该用环境变量 / secrets 管理，不要提交到 git
5. 子 Key 也能填进 `OPENAI_API_KEY`，和 master key 的用法完全一样，区别见下一节

**自己生成一个 master key**

LiteLLM **不发放** master key，也不用注册；它就是**你自己随便生成的一串随机码**，只要满足：

- 以 `sk-` 开头
- 足够长（建议 32 字节随机数，也就是 64 个十六进制字符）

用下面任意一条生成（每次输出都不一样）：

```powershell
# PowerShell（5.1 / 7 都能用）
$b = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
"sk-" + ([BitConverter]::ToString($b) -replace '-','').ToLower()
```

```powershell
# Python（项目已有 uv 环境）
uv run python -c "import secrets; print('sk-' + secrets.token_hex(32))"
```

```text
sk-8f3c1e...（示例：sk- 加上 64 位十六进制，共 67 个字符）
```

生成后**两处都要改**：

1. `docker-compose.yml` → `LITELLM_MASTER_KEY`
2. `.env` → `OPENAI_API_KEY`

然后重启网关：

```powershell
make restart SERVICE=litellm
```

> 仓库里现在的 `sk-d09e0b...` 就是一段 32 字节随机数的十六进制，只是为了本地开箱即用。
> 如果这个项目要给别人看或部署，建议换成自己生成的。

**顺带说 `LITELLM_SALT_KEY`**

`docker-compose.yml` 里还有一个 `LITELLM_SALT_KEY`，它**不是**访问凭证，而是 LiteLLM
**加密数据库里子 Key** 用的盐。同样是随机码，生成方式一样：

```powershell
uv run python -c "import secrets; print(secrets.token_hex(32))"
```

两点注意：

- `LITELLM_SALT_KEY` **不需要和 master key 一样**，各生成各的
- 已经有子 Key 之后**不要随便改 SALT_KEY**，否则数据库里存过的子 Key 会解不开；改 master key 不影响已创建的子 Key

#### 3.11.3 （可选）在 UI 里创建子 Key

如果你在 UI 里看到的是 `Virtual Keys`（有些版本叫 `Keys`）→ `Create Key` 页面，那是在**创建子 Key**，不是 master key。

适用场景：

- 想给项目 / 同事单独发一个 Key，能随时吊销
- 想限制预算（`Budget`）、限速（`RPM / TPM`）、限定只能访问某几个模型
- 不想把 root 权限的 master key 写进 `.env`

操作：

1. 打开 <http://localhost:4000/ui>，用 `admin` / `123456` 登录
2. 左侧进入 `Virtual Keys` → `Create Key`（或 `Create New Key`）
3. 按需填写：
   - **Key Alias**：备注名，例如 `deal-pilot-local`
   - **Models**：允许访问的模型，建议只勾你要用的
   - **Max Budget / Budget Duration**：预算上限，本地调试可留空
   - **RPM / TPM Limit**：限速，本地调试可留空
4. 创建后复制生成的 `sk-...`

> 子 Key 通常**只在创建时完整显示一次**。没复制到就删掉重新建一个。

拿到子 Key 后，把它填到 `.env` 的 `OPENAI_API_KEY` 即可，和 master key 用法一模一样：

```dotenv
OPENAI_API_KEY=sk-你刚创建的子Key
```

| | master key | 子 Key |
|---|---|---|
| 来源 | `docker-compose.yml` | LiteLLM UI 创建 |
| 权限 | 全部（含管理接口） | 可限制模型 / 预算 / 速率 |
| 能否吊销 | 改 compose 并重启 | UI 里一键删除 |
| 适合 | 本机自用、调试 | 多人、演示、接近生产 |

> 本项目 README 后面默认用 master key，少一步操作。你在面试或演示时，可以说清楚"生产会换成子 Key + 预算限制"，这是加分项。

#### 3.11.4 确认网关活着，且当前是空的

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }

# 1) 健康检查
(Invoke-WebRequest http://127.0.0.1:4000/health/liveliness -UseBasicParsing).StatusCode   # 200

# 2) 看看现在有哪些模型
Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw
```

刚启动时返回空列表，这是正常的：

```json
{"data":[],"object":"list"}
```

> 这一步返回 401，说明 Key 不对（master key 或子 Key）；返回 200 但列表为空，说明还没加模型，继续往下。

#### 3.11.5 方式 A（推荐）：写进 `litellm-config.yaml`

适合长期使用、要提交到仓库、要在简历/面试里展示的项目。配置在文件里看得见、可回滚，
`make clean` 删数据卷也不会丢。

##### A1. 把上游 Key 放进 `.env`

打开 `.env`，在文件末尾加上你要用的厂商 Key：

```dotenv
# ---------- LiteLLM 上游模型 Key（只给网关容器用）----------
DASHSCOPE_API_KEY=sk-你的百炼Key
DEEPSEEK_API_KEY=
UPSTREAM_OPENAI_API_KEY=
```

只填你要用的那一个，其他留空即可。这些变量会通过 `docker-compose.yml` 里的

```yaml
DASHSCOPE_API_KEY: ${DASHSCOPE_API_KEY:-}
```

透传给 LiteLLM 容器，**不会传给 Agent 进程**。

##### A2. 编辑 `litellm-config.yaml`

仓库里已经放好了注释示例，把要用的那段取消注释、改掉模型名即可：

```yaml
model_list:
  # ---- 阿里云百炼（通义千问）----
  - model_name: qwen-plus                          # 网关对外名字（.env 的 OPENAI_DEFAULT_MODEL）
    litellm_params:
      model: openai/qwen-plus                      # 上游真实模型名
      api_base: https://dashscope.aliyuncs.com/compatible-mode/v1
      api_key: os.environ/DASHSCOPE_API_KEY        # 从 .env 读，不落盘

  # ---- DeepSeek ----
  # - model_name: deepseek-chat
  #   litellm_params:
  #     model: openai/deepseek-chat
  #     api_base: https://api.deepseek.com/v1
  #     api_key: os.environ/DEEPSEEK_API_KEY

  # ---- OpenAI ----
  # - model_name: gpt-4o-mini
  #   litellm_params:
  #     model: openai/gpt-4o-mini
  #     api_key: os.environ/UPSTREAM_OPENAI_API_KEY

router_settings:
  optional_pre_call_checks:
    - session_affinity
```

字段说明：

| 字段 | 含义 | 注意 |
|------|------|------|
| `model_name` | 网关对外的名字 | `.env` 的 `OPENAI_DEFAULT_MODEL` 必须和它一字不差 |
| `litellm_params.model` | 上游真实模型 | 统一写成 `openai/<模型名>` + `api_base`，兼容性最好 |
| `litellm_params.api_base` | 上游地址 | 一般以 `/v1` 结尾，不要写成 `.../chat/completions` |
| `litellm_params.api_key` | 上游 Key | 用 `os.environ/变量名` 引用 `.env`，不要把 Key 直接写进文件 |

> `model: openai/xxx` 的意思是"用 OpenAI 兼容协议去调"，并不代表一定是 OpenAI 官方。
> 百炼、DeepSeek、Moonshot、硅基流动等都有 OpenAI 兼容端点，都这么写。
>
> **不要把真实 Key 直接写进 `litellm-config.yaml`**，这个文件是要提交到 git 的。
> 走 `os.environ/...`，Key 只留在被 `.gitignore` 忽略的 `.env` 里。

##### A3. 重启 LiteLLM

配置文件是挂载进容器的，改完必须重启才生效：

```powershell
make restart SERVICE=litellm
```

##### A4. 验证模型已经加载

```powershell
$gw = @{ Authorization = "Bearer sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9" }
(Invoke-RestMethod http://127.0.0.1:4000/v1/models -Headers $gw).data.id
```

成功标志：输出你配置的 `model_name`，例如：

```text
qwen-plus
```

看不到就 `make logs SERVICE=litellm` 看报错，多半是 YAML 缩进或者环境变量名写错了。

#### 3.11.6 方式 B：在 LiteLLM UI 里添加（临时试用）

适合只想先跑通、暂时不打算提交配置的情况。UI 添加的模型存在 LiteLLM 自己的 Postgres 数据卷里。

> UI 里有两个容易混的页面：
> - `Models`：**加模型**，这一节用这个
> - `Virtual Keys`：**发 Key**，见 [3.11.3](#3113-可选在-ui-里创建子-key)
>
> 不管哪个页面，都**不能创建 master key**，master key 只在 `docker-compose.yml` 里。

1. 打开 <http://localhost:4000/ui>，用 `admin` / `123456` 登录
2. 进入 `Models` → `Add Model`
3. 填四样东西（不同版本字段名略有差异，认准含义即可）：
   - **Public Model Name**：网关对外名字，例如 `qwen-plus`
   - **Provider**：上游服务商；没有对应选项就选 `OpenAI-Compatible`
   - **API Base / Base URL**：上游服务地址，例如 `https://dashscope.aliyuncs.com/compatible-mode/v1`
   - **API Key**：上游厂商的 Key（**不是**网关的 master key）
4. 保存，然后同样用 A4 的命令验证

注意：

- 不要和 `litellm-config.yaml` 里的 `model_name` 重名
- `make down` 不会丢，`make clean` 会连数据卷一起删掉
- UI 里加的模型不会出现在 git 里，换台机器要重新加

#### 3.11.7 网关常见错误

| 现象 | 原因 | 处理 |
|------|------|------|
| `/v1/models` 返回 `401` | 请求头里的 Key 不对 | 用 `docker-compose.yml` 的 `LITELLM_MASTER_KEY`，或 3.11.3 里创建的子 Key |
| `/v1/models` 返回空列表 | 模型没加载 | 检查 YAML 缩进、`make restart SERVICE=litellm`、`make logs SERVICE=litellm` |
| `model not found` / `404` | `.env` 的 `OPENAI_DEFAULT_MODEL` 和 `model_name` 不一致 | 两边逐字对照，大小写也要一致 |
| 上游返回 `401` | 厂商 Key 错、过期，或没透传到容器 | 确认 `.env` 里的 Key 已填，且 compose 里有对应的透传行 |
| 上游返回 `404` | `api_base` 错了 | 多写/少写了 `/v1`，或写成了 `/chat/completions` 结尾 |
| 请求超时 | 容器访问不了外网 | Docker Desktop 配代理，见 [Q10](#q10-docker-拉镜像超时--卡住) |
| 日志里 `No models configured` | 整个 `model_list` 被注释掉了 | 至少保留一个模型再重启 |

> 排错顺序永远是：**先 `/v1/models` 看模型有没有 → 再 `/v1/chat/completions` 看上游通不通 → 最后才启动 Agent**。

> ✅ **完成这一步后**：网关里有一个能用的模型，用 master key 就能调通上游厂商的模型。

### 3.12 把网关配置写进 `.env`

编辑 `.env`，填这四项（`qwen-plus` 换成你在 3.11 里配的 `model_name`）：

```dotenv
OPENAI_BASE_URL=http://127.0.0.1:4000/v1
OPENAI_API_KEY=sk-d09e0b617046b7d70e5b25ae2da70a5c1154ac2f4d89ad8a1a77447edb77e3b9
OPENAI_DEFAULT_MODEL=qwen-plus
NACOS_PASSWORD=<你在 3.10 设置的密码>
```

说明：

- `OPENAI_BASE_URL` 填**网关地址**，不是上游地址
- `OPENAI_API_KEY` 填 LiteLLM 的 **master key**（就是上面这一长串），不是上游厂商的 Key
- `OPENAI_DEFAULT_MODEL` 必须和 3.11 里的 **`model_name` / Public Model Name** 一模一样
- master key 以 `docker-compose.yml` 里的 `LITELLM_MASTER_KEY` 为准；改过 compose 就要跟着改
- 上游厂商的 Key 在 3.11 已经放进 `.env` 的 `DASHSCOPE_API_KEY` 等变量里，这里不用重复

检查这些都不是空：

```powershell
Select-String -Path .env -Pattern '^OPENAI_|^NACOS_PASSWORD|^DASHSCOPE_API_KEY'
```

最后**先不启动 Agent**，直接通过网关发一条消息，确认"网关 → 上游模型"整条链路是通的（`model` 同样换成你的 `model_name`）：

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
> 常见原因：模型名和 3.11 里不一致、上游 Key 错、上游地址多了或少了 `/v1`。

> ✅ **完成这一步后**：`.env` 里模型地址、master key、模型名、Nacos 密码都齐了，Agent 具备启动条件。

### 3.13 启动 Agent

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

> ✅ **完成这一步后**：Agent 服务已经在 `127.0.0.1:2024` 跑起来，可以接受 HTTP 请求了。

### 3.14 验证 Agent 服务

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

> ✅ **完成这一步后**：你确认了服务活着，并且三张图（主 Agent、清理 Trace、飞书索引）都注册成功。

### 3.15 发出第一条真实消息

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
| `model not found` / `404` | 模型名不对 | `OPENAI_DEFAULT_MODEL` 必须和 3.11 的 `model_name` 一致 |
| `Incorrect API key` / `401` | Key 不对 | 直连填服务商 Key；走 LiteLLM 填 master key |
| `400 ... enable_thinking` | 该模型不支持思考参数 | 见 [Q11](#q11-模型报-400-unknown-parameter-enable_thinking) |

> ✅ **完成这一步后**：你已经完整跑通了「Agent → LiteLLM → 上游模型」这条链路，项目可以从头到尾用了。

### 3.16 （可选）在 Langfuse 里看到 Trace

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

> ✅ **完成这一步后**：你能在 Langfuse 里看到每次对话的 Trace、Token 和耗时，方便排查和展示。

### 3.17 （可选）在 Nacos 里建 AgentSpec

不做这一步，Agent 就是一个"没有 system prompt、没有工具"的裸模型，仍然能回答，
但不会用工具、也没有人设。想要完整形态，按 [第 6 节](#6-nacos-里需要配置什么) 建一个 `main_agent`。

> ✅ **完成这一步后**：Agent 有了 system prompt、工具和子 Agent，才是这个项目设计里的完整形态。

### 3.18 验收清单

全部打勾就说明**完整跑通**了：

- [ ] `uv run python -V` 输出 `Python 3.13.11`
- [ ] `make test` 输出 `348 passed`
- [ ] `make ps` 显示 15 个容器，该 healthy 的都 healthy
- [ ] Nacos 能登录，`.env` 里的 `NACOS_PASSWORD` 和页面一致
- [ ] `/v1/models` 能看到你在 3.11 里配置的模型
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
| `OPENAI_API_KEY` | 模型 Key | 填 LiteLLM 的 `LITELLM_MASTER_KEY` 或 UI 创建的子 Key；直连模式填服务商 Key |
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
| `DASHSCOPE_API_KEY` / `DEEPSEEK_API_KEY` / `UPSTREAM_OPENAI_API_KEY` | 网关没有上游 Key，调模型时报 401 |
| `OPEN_SANDBOX_API_KEY` | `make up` 直接报错退出（compose 要求必填）。它是自建服务的访问口令，自己定随机串即可，不是官方发放的 |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | 文件上传、沙箱共享卷不可用 |

### 5.3 模型网关

**默认：走 LiteLLM**（和 [3.11](#311-配置-litellm-网关添加模型) 对应）

推荐用配置文件的方式，Key 走环境变量、不进 git：

1. `.env` 里加上游 Key（只填要用的）：

```dotenv
DASHSCOPE_API_KEY=sk-xxx
DEEPSEEK_API_KEY=
UPSTREAM_OPENAI_API_KEY=
```

2. `litellm-config.yaml` 里配置 `model_list`，`api_key` 写 `os.environ/变量名`
3. `make restart SERVICE=litellm`
4. `GET /v1/models` 能看到模型后再填：

```dotenv
OPENAI_BASE_URL=http://127.0.0.1:4000/v1
OPENAI_API_KEY=<docker-compose.yml 里的 LITELLM_MASTER_KEY>
OPENAI_DEFAULT_MODEL=<litellm-config.yaml 里的 model_name>
```

好处：模型切换、限流、花销统计、Langfuse 追踪都在一起，也是本项目的默认设计。
完整字段说明和排错见 [3.11.5](#3115-方式-a推荐写进-litellm-configyaml)。

**可选：直连 OpenAI 兼容服务（跳过 3.11）**

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

返回空就说明模型还没加，回到 [3.11](#311-配置-litellm-网关添加模型)。

- 走 LiteLLM：模型名要和 `OPENAI_DEFAULT_MODEL` 完全一致（= `litellm-config.yaml` 的 `model_name`，或 UI 里的 Public Model Name）
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

### Q12. `uv trampoline failed to canonicalize script path`

完整报错：

```text
error: uv trampoline failed to canonicalize script path
make: *** [Makefile:61: test] Error 1
```

**原因**：`.venv` 是在别的目录创建的，之后整个项目文件夹被移动/重命名了。
uv 在 Windows 上生成的 `pytest.exe`、`langgraph.exe` 这类启动器里记录的是**绝对路径**，
文件夹一挪，它们就找不到自己该启动的脚本了。

先确认是不是这个原因：

```powershell
# 有没有报错，报错就是启动器坏了
.\.venv\Scripts\pytest.exe --version

# 这条能正常输出 9.x.x，说明虚拟环境本身没坏
.\.venv\Scripts\python.exe -m pytest --version
```

前一条报 `uv trampoline...`、后一条正常，就可以确定是启动器问题。

**处理**：重新生成启动器（不用重新下载 Python）：

```powershell
uv sync --reinstall
```

如果报 `拒绝访问 python.exe`，说明 VS Code 的 Python 插件（black-formatter 等）正占着这个环境。
先关掉 VS Code 或结束对应进程，再执行。

如果 `uv sync --reinstall` 卡在下载依赖，见 [Q10](#q10-docker-拉镜像超时--卡住) 的换源思路；
本机 `~/.config/uv/uv.toml`（或 `%APPDATA%\uv\uv.toml`）里默认源是清华镜像时，
临时用官方源验证可以：

```powershell
uv sync --reinstall --default-index https://pypi.org/simple
```

> 注意：`--default-index` 会把 `uv.lock` 里的源地址一起改写。
> 验证完记得 `git checkout -- uv.lock` 还原，不要把换源结果提交上去。

**彻底一点**的做法是删掉 `.venv` 重建（需要先结束占用它的进程）：

```powershell
Remove-Item .venv -Recurse -Force
uv sync
make test
```

**预防**：`.venv` 不要跟着项目一起拷贝或移动。换电脑、换目录后，直接删掉旧 `.venv` 重新 `uv sync`。

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
| `make restart SERVICE=litellm` | 重启指定服务（改完 `litellm-config.yaml` 用） |
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
