# InstaGraph 部署指南

## 概述
InstaGraph 是一个基于 Flask 的 Web 应用程序，用于生成和可视化知识图谱。本文档提供了完整的部署方案。

## 环境要求
- Python 3.8+
- pip 包管理器
- OpenAI API 密钥（用于 AI 功能）

## 部署方案

### 1. 快速部署（推荐）
使用提供的部署脚本：

```powershell
# 直接部署模式（开发/测试环境）
.\deploy.ps1 -Mode direct -Port 8080 -Database none

# Docker 部署模式（生产环境）
.\deploy.ps1 -Mode docker -Port 8080 -Database postgres

# 开发模式
.\deploy.ps1 -Mode dev -Port 5000 -Database none
```

### 2. 手动部署步骤

#### 步骤 1: 环境配置
1. 确保 `.env` 文件存在并包含必要的环境变量：
```
OPENAI_API_KEY=your_openai_api_key_here
FLASK_ENV=production
FLASK_DEBUG=false
```

#### 步骤 2: 安装依赖
```bash
pip install -r requirements.txt
```

主要依赖包括：
- Flask
- openai>=1.0.0
- instructor>=1.0.0
- requests
- python-dotenv

#### 步骤 3: 启动应用
```bash
# 开发模式
python main.py --port 8080 --graph none

# 生产模式（推荐使用 WSGI 服务器）
gunicorn -w 4 -b 0.0.0.0:8080 main:app
```

## 部署验证

使用提供的验证脚本检查部署状态：

```powershell
.\verify-deployment.ps1 -BaseUrl "http://localhost:8080" -Timeout 30
```

验证脚本会测试以下端点：
- ✅ 健康检查 (`/health`)
- ✅ 主页 (`/`)
- ✅ API 端点 (`/get_response_data`)
- ✅ 图形数据 (`/get_graph_data`)
- ✅ 图形历史 (`/get_graph_history`)
- ⚠️ Graphviz 端点 (`/graphviz`) - 需要特定参数

## 生产环境配置

### 使用 Gunicorn（推荐）
```bash
# 安装 Gunicorn
pip install gunicorn

# 启动生产服务器
gunicorn -w 4 -b 0.0.0.0:8080 --timeout 120 main:app
```

### 使用 Docker
```dockerfile
# Dockerfile 示例
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8080", "main:app"]
```

## 环境变量说明

| 变量名 | 必需 | 说明 |
|--------|------|------|
| `OPENAI_API_KEY` | 是 | OpenAI API 密钥 |
| `FLASK_ENV` | 否 | Flask 环境（development/production） |
| `FLASK_DEBUG` | 否 | 调试模式（true/false） |

## 故障排除

### 常见问题

1. **ImportError: cannot import name 'OpenAI' from 'openai'**
   - 解决方案：升级 openai 库到 1.x 版本
   ```bash
   pip install openai>=1.0.0
   ```

2. **instructor 版本不兼容**
   - 解决方案：升级 instructor 库
   ```bash
   pip install instructor>=1.0.0
   ```

3. **端口被占用**
   - 解决方案：更改端口或停止占用端口的进程
   ```bash
   netstat -ano | findstr :8080
   ```

4. **OpenAI API 密钥未配置**
   - 解决方案：在 `.env` 文件中设置正确的 API 密钥

### 日志查看
应用日志会输出到控制台。在生产环境中，建议将日志重定向到文件：

```bash
gunicorn -w 4 -b 0.0.0.0:8080 main:app > app.log 2>&1
```

## 性能优化

1. **使用多进程**：在生产环境中使用 Gunicorn 的多进程模式
2. **反向代理**：使用 Nginx 作为反向代理
3. **缓存**：考虑使用 Redis 缓存频繁请求的数据
4. **负载均衡**：对于高流量场景，使用负载均衡器

## 安全建议

1. **环境变量**：不要在代码中硬编码敏感信息
2. **HTTPS**：在生产环境中使用 HTTPS
3. **防火墙**：配置适当的防火墙规则
4. **更新依赖**：定期更新依赖包以修复安全漏洞

## 监控

建议监控以下指标：
- 应用响应时间
- 错误率
- CPU 和内存使用率
- API 调用频率

健康检查端点：`GET /health`

## 支持

如果遇到问题，请检查：
1. 应用日志
2. 环境变量配置
3. 依赖包版本
4. 网络连接

---

**部署状态**: ✅ 已验证 - 核心功能正常工作
**最后更新**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')