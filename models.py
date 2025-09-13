from typing import Any, Dict, List

from pydantic import BaseModel, Field


class Metadata(BaseModel):
    createdDate: str = Field(
        ..., description="The date the knowledge graph was created"
    )
    lastUpdated: str = Field(
        ..., description="The date the knowledge graph was last updated"
    )
    description: str = Field(..., description="Description of the knowledge graph")


class Node(BaseModel):
    id: str = Field(..., description="Unique identifier for the node")
    label: str = Field(..., description="Label for the node")
    type: str = Field(..., description="Type of the node")
    color: str = Field(..., description="Color for the node")
    properties: Dict[str, Any] = Field(
        {}, description="Additional attributes for the node"
    )


class Edge(BaseModel):
    # WARING: Notice that this is "from_", not "from"
    from_: str = Field(..., alias="from", description="Origin node ID")
    to: str = Field(..., description="Destination node ID")
    relationship: str = Field(..., description="Type of relationship between the nodes")
    direction: str = Field(..., description="Direction of the relationship")
    color: str = Field(..., description="Color for the edge")
    properties: Dict[str, Any] = Field(
        {}, description="Additional attributes for the edge"
    )


class KnowledgeGraph(BaseModel):
    """生成包含实体和关系的知识图谱。
    要求：
    1. 所有节点标签(label)和关系描述(relationship)必须使用中文（专有名词可保留英文）
    2. 节点类型(type)要详细准确，体现实体的具体分类
    3. 关系描述要具体明确，避免使用模糊的关系词
    4. 尽可能包含更多相关实体和关系，确保知识图谱的完整性和深度
    5. 使用颜色来区分不同的节点或边的类型/类别
    6. 始终提供与黑色字体搭配良好的浅色调颜色
    """

    metadata: Metadata = Field(..., description="Metadata for the knowledge graph")
    nodes: List[Node] = Field(..., description="List of nodes in the knowledge graph")
    edges: List[Edge] = Field(..., description="List of edges in the knowledge graph")
