# Deal Pilot 开发服务器启动脚本（Windows）
# 作用：设置 UTF-8 环境变量后启动 langgraph dev
# 用法：
#   .\dev.ps1            # 默认 2024 端口
#   .\dev.ps1 -Port 8000 # 指定端口
param(
    [int]$Port = 2024
)

$ErrorActionPreference = "Stop"

# 中文版 Windows 默认 GBK 编码，langgraph-api 读取内置 JSON 时会报
# UnicodeDecodeError，必须强制 Python 使用 UTF-8
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

Write-Host "启动 LangGraph 开发服务器: http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "API 文档: http://127.0.0.1:$Port/docs" -ForegroundColor DarkGray
Write-Host "按 Ctrl+C 停止" -ForegroundColor DarkGray

uv run langgraph dev --host 127.0.0.1 --port $Port --no-browser
