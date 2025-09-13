#!/bin/bash

# InstaGraph 部署验证脚本
# 用于验证部署后的服务状态和功能

# 默认参数
BASE_URL="http://localhost:8080"
TIMEOUT=30

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            BASE_URL="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "InstaGraph 部署验证脚本"
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -u, --url       服务基础URL [默认: http://localhost:8080]"
            echo "  -t, --timeout   请求超时时间(秒) [默认: 30]"
            echo "  -h, --help      显示帮助信息"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

echo "=== InstaGraph 部署验证脚本 ==="
echo "测试目标: $BASE_URL"
echo "超时时间: $TIMEOUT 秒"
echo ""

tests_passed=0
tests_total=0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 测试函数
test_endpoint() {
    local name="$1"
    local url="$2"
    local method="${3:-GET}"
    local data="$4"
    local expected_status="${5:-200}"
    
    ((tests_total++))
    echo -e "${CYAN}测试 $tests_total : $name${NC}"
    
    local curl_cmd="curl -s -w '%{http_code}' -m $TIMEOUT"
    
    if [ "$method" = "POST" ]; then
        curl_cmd="$curl_cmd -X POST"
        if [ -n "$data" ]; then
            curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$data'"
        fi
    fi
    
    local response
    response=$(eval "$curl_cmd '$url'" 2>/dev/null)
    local status_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "  ${GREEN}✓ 通过 (状态码: $status_code)${NC}"
        ((tests_passed++))
        return 0
    else
        echo -e "  ${RED}✗ 失败 (期望状态码: $expected_status, 实际: $status_code)${NC}"
        if [ -n "$body" ] && [ ${#body} -lt 200 ]; then
            echo -e "  ${RED}响应: $body${NC}"
        fi
        return 1
    fi
}

# 检查curl是否可用
if ! command -v curl &> /dev/null; then
    echo -e "${RED}错误: 未安装curl，无法进行测试${NC}"
    exit 1
fi

# 等待服务启动
echo -e "${YELLOW}等待服务启动...${NC}"
sleep 5

# 1. 健康检查
test_endpoint "健康检查端点" "$BASE_URL/health"

# 2. 主页访问
test_endpoint "主页访问" "$BASE_URL/"

# 3. API 端点测试
echo -e "${CYAN}测试 $((tests_total + 1)) : API 端点功能${NC}"
((tests_total++))

api_data='{"user_input": "测试知识图谱生成"}'
api_response=$(curl -s -w '%{http_code}' -m $TIMEOUT -X POST -H 'Content-Type: application/json' -d "$api_data" "$BASE_URL/get_response_data" 2>/dev/null)
api_status="${api_response: -3}"
api_body="${api_response%???}"

if [ "$api_status" = "200" ]; then
    # 检查响应是否包含nodes和edges
    if echo "$api_body" | grep -q '"nodes"' && echo "$api_body" | grep -q '"edges"'; then
        echo -e "  ${GREEN}✓ 通过 (成功生成知识图谱)${NC}"
        ((tests_passed++))
    else
        echo -e "  ${RED}✗ 失败 (响应格式不正确)${NC}"
    fi
elif [ "$api_status" = "401" ]; then
    echo -e "  ${YELLOW}⚠ 跳过 (API密钥未配置或无效)${NC}"
    ((tests_total--))
elif [ "$api_status" = "402" ]; then
    echo -e "  ${YELLOW}⚠ 跳过 (API余额不足)${NC}"
    ((tests_total--))
else
    echo -e "  ${RED}✗ 失败 (状态码: $api_status)${NC}"
fi

# 4. 图形数据端点
test_endpoint "图形数据端点" "$BASE_URL/get_graph_data" "POST" '{}'

# 5. 图形历史端点
test_endpoint "图形历史端点" "$BASE_URL/get_graph_history"

# 6. Graphviz 端点
test_endpoint "Graphviz 可视化端点" "$BASE_URL/graphviz" "POST" '{}'

# 测试结果汇总
echo ""
echo -e "${GREEN}=== 测试结果汇总 ===${NC}"
echo -e "${YELLOW}通过测试: $tests_passed / $tests_total${NC}"

if [ $tests_passed -eq $tests_total ]; then
    echo -e "${GREEN}🎉 所有测试通过！部署成功！${NC}"
    exit 0
elif [ $tests_passed -ge $((tests_total * 8 / 10)) ]; then
    echo -e "${YELLOW}⚠️  大部分测试通过，部署基本成功，但有一些问题需要检查${NC}"
    exit 1
else
    echo -e "${RED}❌ 多个测试失败，部署可能有问题${NC}"
    exit 2
fi

# 额外的系统信息
echo ""
echo -e "${GREEN}=== 系统信息 ===${NC}"
echo -e "${YELLOW}Bash 版本: $BASH_VERSION${NC}"
echo -e "${YELLOW}操作系统: $(uname -s) $(uname -r)${NC}"
echo -e "${YELLOW}当前时间: $(date)${NC}"