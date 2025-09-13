#!/bin/bash

# InstaGraph 自动部署脚本
# 适用于Linux和macOS环境

# 默认参数
MODE="direct"
PORT=8080
DATABASE="none"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -h|--help)
            echo "InstaGraph 部署脚本"
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -m, --mode      部署模式 (docker|direct|dev) [默认: direct]"
            echo "  -p, --port      端口号 [默认: 8080]"
            echo "  -d, --database  数据库类型 (neo4j|falkordb|none) [默认: none]"
            echo "  -h, --help      显示帮助信息"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 验证参数
if [[ ! "$MODE" =~ ^(docker|direct|dev)$ ]]; then
    echo "错误: 无效的部署模式 '$MODE'"
    echo "支持的模式: docker, direct, dev"
    exit 1
fi

if [[ ! "$DATABASE" =~ ^(neo4j|falkordb|none)$ ]]; then
    echo "错误: 无效的数据库类型 '$DATABASE'"
    echo "支持的数据库: neo4j, falkordb, none"
    exit 1
fi

echo "=== InstaGraph 部署脚本 ==="
echo "部署模式: $MODE"
echo "端口: $PORT"
echo "数据库: $DATABASE"
echo ""

# 检查.env文件
if [ ! -f ".env" ]; then
    echo "未找到.env文件，正在创建..."
    if [ -f ".env.example" ]; then
        cp ".env.example" ".env"
        echo "请编辑.env文件配置必要的环境变量（特别是OPENAI_API_KEY）"
        echo "配置完成后重新运行此脚本"
        exit 1
    else
        echo "未找到.env.example文件"
        exit 1
    fi
fi

# 检查环境变量
if ! grep -q "OPENAI_API_KEY=.\+" ".env"; then
    echo "警告: OPENAI_API_KEY未配置或为空"
    echo "请编辑.env文件配置API密钥"
    exit 1
fi

case $MODE in
    "docker")
        echo "使用Docker部署（生产模式）..."
        
        # 检查Docker
        if ! command -v docker &> /dev/null; then
            echo "错误: 未安装Docker"
            exit 1
        fi
        
        if ! command -v docker-compose &> /dev/null; then
            echo "错误: 未安装Docker Compose"
            exit 1
        fi
        
        # 停止现有容器
        echo "停止现有容器..."
        cd docker
        docker-compose -f docker-compose.yml down 2>/dev/null
        
        # 构建并启动
        echo "构建并启动容器..."
        docker-compose -f docker-compose.yml up --build -d
        
        if [ $? -eq 0 ]; then
            echo "Docker部署成功！"
            echo "访问地址: http://localhost:$PORT"
        else
            echo "Docker部署失败"
            exit 1
        fi
        
        cd ..
        ;;
        
    "dev")
        echo "使用Docker部署（开发模式）..."
        
        # 检查Docker
        if ! command -v docker &> /dev/null; then
            echo "错误: 未安装Docker"
            exit 1
        fi
        
        if ! command -v docker-compose &> /dev/null; then
            echo "错误: 未安装Docker Compose"
            exit 1
        fi
        
        # 停止现有容器
        echo "停止现有容器..."
        cd docker
        docker-compose -f docker-compose-dev.yml down 2>/dev/null
        
        # 构建并启动
        echo "构建并启动开发容器..."
        docker-compose -f docker-compose-dev.yml up --build
        
        cd ..
        ;;
        
    "direct")
        echo "直接部署模式..."
        
        # 检查Python
        if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
            echo "错误: 未安装Python"
            exit 1
        fi
        
        # 使用python3或python
        PYTHON_CMD="python3"
        if ! command -v python3 &> /dev/null; then
            PYTHON_CMD="python"
        fi
        
        echo "Python版本: $($PYTHON_CMD --version)"
        
        # 检查pip
        if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
            echo "错误: 未安装pip"
            exit 1
        fi
        
        PIP_CMD="pip3"
        if ! command -v pip3 &> /dev/null; then
            PIP_CMD="pip"
        fi
        
        # 安装依赖
        echo "安装Python依赖..."
        $PIP_CMD install -r requirements.txt
        
        if [ $? -ne 0 ]; then
            echo "依赖安装失败"
            exit 1
        fi
        
        # 启动服务
        echo "启动InstaGraph服务..."
        echo "访问地址: http://localhost:$PORT"
        echo "按Ctrl+C停止服务"
        echo ""
        
        $PYTHON_CMD main.py --port $PORT --graph $DATABASE
        ;;
esac

echo "部署完成！"