import argparse
import json
import logging
import os
import re
import time

import instructor
from openai import OpenAI
import openai
import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request
from graphviz import Digraph

from drivers.driver import Driver
from drivers.falkordb import FalkorDB
from drivers.neo4j import Neo4j
from models import KnowledgeGraph

load_dotenv()

app = Flask(__name__)

# Initialize OpenAI client with instructor
openai_client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY"),
    base_url=os.getenv("OPENAI_API_BASE", "https://openrouter.ai/api/v1")
)
client = instructor.patch(openai_client)
response_data = ""

# If a Graph database set, then driver is used to store information
driver: Driver | None = None


# Function to scrape text from a website


def scrape_text_from_url(url):
    response = requests.get(url)
    if response.status_code != 200:
        return "Error: Could not retrieve content from URL."
    soup = BeautifulSoup(response.text, "html.parser")
    paragraphs = soup.find_all("p")
    text = " ".join([p.get_text() for p in paragraphs])
    logging.info("web scrape done")
    return text


# Function to check user plan


def check_if_free_plan():
    """
    receive USER_PLAN from .env.
    Added default None, as this project won't be in free plan in production mode.

    Returns:
        bool: _description_
    """
    return os.environ.get("USER_PLAN", None) == "free"


# Rate limiting


@app.after_request
def add_header(response):
    """
    add response header if free plan.

    Args:
        response (_type_): _description_

    Returns:
        _type_: _description_
    """
    if check_if_free_plan():
        response.headers["Retry-After"] = 20
    return response


def correct_json(json_str):
    """
    Corrects the JSON response from OpenAI to be valid JSON by removing trailing commas
    """
    while ",\s*}" in json_str or ",\s*]" in json_str:  # noqa: W605
        json_str = re.sub(r",\s*}", "}", json_str)
        json_str = re.sub(r",\s*]", "]", json_str)

    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        logging.error(
            "SanitizationError: %s for JSON: %s", str(e), json_str, exc_info=True
        )
        return None


@app.route("/get_response_data", methods=["POST"])
def get_response_data():
    global response_data
    user_input = request.json.get("user_input", "")
    if not user_input:
        return jsonify({"error": "No input provided"}), 400
    if user_input.startswith("http"):
        user_input = scrape_text_from_url(user_input)

    if user_input.startswith("+"):
        prompt = "\n".join(
            [
                "请根据以下指令更新知识图谱，确保使用中文描述所有节点和关系（专有名词可保留英文）：",
                json.dumps(
                    dict(instruction=user_input[1:], knowledge_graph=response_data)
                ),
            ]
        )
    else:
        prompt = f"请帮我理解以下内容，生成一个详细、高质量的知识图谱。要求：1. 所有节点标签和关系描述必须使用中文（专有名词可保留英文）；2. 节点类型要详细准确；3. 关系描述要具体明确；4. 尽可能包含更多相关实体和关系，确保知识图谱的完整性和深度。内容：{user_input}"

    logging.info("starting openai call: %s", prompt)
    try:
        completion: KnowledgeGraph = client.chat.completions.create(
            model="gpt-3.5-turbo-16k",
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
            response_model=KnowledgeGraph,
        )

        # Its now a dict, no need to worry about json loading so many times
        response_data = completion.model_dump()

        # copy "from_" prop to "from" prop on all edges
        edges = response_data["edges"]

        def _restore(e):
            e["from"] = e["from_"]
            return e

        response_data["edges"] = [_restore(e) for e in edges]

    except openai.RateLimitError as e:
        # request limit exceeded or something.
        logging.warning("%s", e)
        return jsonify({"error": "API rate limit exceeded. Please try again later."}), 429
    except openai.AuthenticationError as e:
        # API key issues
        logging.error("Authentication error: %s", e)
        return jsonify({"error": "API authentication failed. Please check your API key."}), 401
    except Exception as e:
        # Check for 402 error (insufficient credits)
        error_message = str(e)
        if "402" in error_message or "credits" in error_message.lower():
            logging.error("Insufficient credits: %s", e)
            return jsonify({"error": "Insufficient API credits. Please add more credits to your OpenRouter account at https://openrouter.ai/settings/credits"}), 402
        # general exception handling
        logging.error("%s", e)
        return jsonify({"error": "An error occurred while processing your request. Please try again."}), 400

    try:
        if driver:
            results = driver.get_response_data(response_data)
            logging.info("Results from Graph:", results)

    except Exception as e:
        logging.error("An error occurred during the Graph operation: %s", e)
        return (
            jsonify(
                {"error": "An error occurred during the Graph operation: {}".format(e)}
            ),
            500,
        )

    return response_data, 200


# Function to visualize the knowledge graph using Graphviz
@app.route("/graphviz", methods=["POST"])
def visualize_knowledge_graph_with_graphviz():
    global response_data
    dot = Digraph(comment="Knowledge Graph")
    response_dict = response_data
    # Add nodes to the graph
    for node in response_dict.get("nodes", []):
        dot.node(node["id"], f"{node['label']} ({node['type']})")

    # Add edges to the graph
    for edge in response_dict.get("edges", []):
        dot.edge(edge["from"], edge["to"], label=edge["relationship"])

    # Render and visualize
    dot.render("knowledge_graph.gv", view=False)
    # Render to PNG format and save it
    dot.format = "png"
    dot.render("static/knowledge_graph", view=False)

    # Construct the URL pointing to the generated PNG
    png_url = f"{request.url_root}static/knowledge_graph.png"

    return jsonify({"png_url": png_url}), 200


@app.route("/get_graph_data", methods=["POST"])
def get_graph_data():
    try:
        if driver:
            (nodes, edges) = driver.get_graph_data()
        else:
            global response_data
            # print(response_data)
            response_dict = response_data
            # Assume response_data is global or passed appropriately
            nodes = [
                {
                    "data": {
                        "id": node["id"],
                        "label": node["label"],
                        "color": node.get("color", "defaultColor"),
                    }
                }
                for node in response_dict["nodes"]
            ]
            edges = [
                {
                    "data": {
                        "source": edge["from"],
                        "target": edge["to"],
                        "label": edge["relationship"],
                        "color": edge.get("color", "defaultColor"),
                    }
                }
                for edge in response_dict["edges"]
            ]
        return jsonify({"elements": {"nodes": nodes, "edges": edges}})
    except Exception:
        return jsonify({"elements": {"nodes": [], "edges": []}})


@app.route("/get_graph_history", methods=["GET"])
def get_graph_history():
    try:
        page = request.args.get("page", default=1, type=int)
        per_page = 10
        skip = (page - 1) * per_page

        result = (
            driver.get_graph_history(skip, per_page)
            if driver
            else {
                "graph_history": [],
                "error": "Graph driver not initialized",
                "graph": False,
            }
        )
        return jsonify(result)
    except Exception as e:
        logging.error("%s", e)
        return jsonify({"error": str(e), "graph": driver is not None}), 500


@app.route("/health")
def health_check():
    """健康检查端点，用于生产环境监控和负载均衡"""
    try:
        # 检查基本服务状态
        status = {
            "status": "healthy",
            "timestamp": int(time.time()),
            "version": "1.0.0",
            "services": {
                "api": "up",
                "openai": "unknown",
                "database": "unknown"
            }
        }
        
        # 检查OpenAI API连接（可选，避免频繁调用）
        if os.getenv("OPENAI_API_KEY"):
            status["services"]["openai"] = "configured"
        
        # 检查数据库连接
        if driver:
            try:
                # 简单的数据库连接测试
                driver.get_graph_data()
                status["services"]["database"] = "up"
            except Exception:
                status["services"]["database"] = "down"
        else:
            status["services"]["database"] = "disabled"
        
        return jsonify(status), 200
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "timestamp": int(time.time())
        }), 503


@app.route("/")
def index():
    return render_template("index.html")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="InstaGraph")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--port", type=int, dest="port_num", default=8080)
    parser.add_argument("--graph", type=str, dest="graph_db", default="neo4j")

    args = parser.parse_args()
    port = args.port_num
    graph = args.graph_db

    if graph.lower() == "neo4j":
        try:
            driver = Neo4j()
        except Exception:
            print("Warning: Neo4j configuration missing, running without graph database")
            driver = None
    elif graph.lower() == "falkordb":
        try:
            driver = FalkorDB()
        except Exception:
            print("Warning: FalkorDB configuration missing, running without graph database")
            driver = None
    else:
        # No graph database specified
        driver = None

    if args.debug:
        app.run(debug=True, host="0.0.0.0", port=port)
    else:
        app.run(host="0.0.0.0", port=port)
