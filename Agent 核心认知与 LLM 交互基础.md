## Agent 核心认知与 LLM 交互基础

### Step 1：概念建立 —— 为什么是 JSON？

在写代码之前，我们需要在脑海中建立一个清晰的认知模型：

- **LLM（大语言模型）**：就像一个被关在黑屋子里的超级大脑。它有极强的理解和生成能力，但它没有手脚，不能自己去查网页、发邮件。
- **Agent（智能体）**：等于 **LLM（大脑） + 工具（手脚） + 记忆（海马体）**。

**核心推论**：为了让“大脑”指挥“手脚”，大脑输出的指令必须是**计算机程序能够精准解析的格式**。人类可以看懂“废话+核心意思”，但程序代码（Python/Java）只能看懂结构化的数据。**JSON 就是目前 LLM 与外部工具沟通的最佳“世界语”。**

### Step 2：提示词（Prompt）剖析

要让大模型稳定输出 JSON，你的 System Prompt 通常需要包含以下“三板斧”：

1. **明确角色**：告诉它是一个数据处理程序，而不是聊天机器人，切断它寒暄的欲望。
2. **提供数据骨架（Schema）**：直接在提示词中给出一个标准的 JSON 示例。
3. **绝对指令（防崩词）**：使用诸如“只输出 JSON”、“不要包含任何解释性文本”、“不要包含 Markdown 代码块标记（如 ```json）”等绝对性字眼。

### Step 3：环境配置

今天的实战我们将使用 Python。请打开你的终端（Terminal 或 CMD），确保安装了官方的请求库：

Bash

```
pip install openai
```

*(注：虽然名字叫 openai，但这是一个通用的 SDK，很多国产优秀大模型如 DeepSeek、智谱、月之暗面等，都完美兼容这个库。)*

### Step 4：实战代码跑通

请新建一个 Python 文件（例如 `day1_agent.py`），将以下代码复制进去。代码中包含了详细的注释，解释了每一个关键参数的意义：

Python

```python
import os
from openai import OpenAI
import json

# 1. 初始化客户端
# 如果你使用的是国内大模型（例如 DeepSeek），只需替换 api_key 和 base_url
client = OpenAI(
    api_key="你的_API_KEY", 
    # base_url="https://api.deepseek.com/v1" # 取消注释并替换为对应模型的 URL
)

# 2. 构造 System Prompt (核心：角色 + 任务 + 强制格式)
system_prompt = """
你是一个专业的数据信息提取API。
你的任务是分析用户的输入文本，提取情绪和核心关键词。
请严格按照以下 JSON 格式输出结果，不要输出任何其他的废话或 Markdown 标记：
{
    "sentiment": "积极/消极/中性",
    "keywords": ["关键词1", "关键词2"]
}
"""

user_input = "今天开启了 Agent 的系统学习，感觉挑战很大，但我非常期待！"

# 3. 调用大模型 API
print("正在呼叫大模型，请稍候...")
response = client.chat.completions.create(
    model="gpt-3.5-turbo", # 替换为你使用的实际模型名称
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_input}
    ],
    # 【Agent 核心技巧 1】：部分模型支持开启强校验 JSON 模式
    response_format={ "type": "json_object" }, 
    # 【Agent 核心技巧 2】：将温度调低，放弃创造力，换取格式的绝对稳定
    temperature=0.1 
)

# 4. 获取并解析结果
result_text = response.choices[0].message.content
print("\n--- 🤖 大模型原始输出 ---")
print(result_text)

# 5. 验证：大模型的输出能否被程序识别？
print("\n--- ⚙️ 程序解析结果 ---")
try:
    # 这一步是后续 Agent 调用工具的关键：把文本变成代码里的字典(Dict)
    parsed_data = json.loads(result_text) 
    print("✅ 解析成功！")
    print(f"识别到的情绪是: {parsed_data['sentiment']}")
    print(f"提取到的关键词: {parsed_data['keywords']}")
except json.JSONDecodeError:
    print("❌ 解析失败，大模型的输出不是合法的 JSON 格式。")
```

## 规划（Planning）与 ReAct 框架

### 第一步：理论筑基 —— 为什么我们需要 ReAct？

在写代码之前，我们需要弄明白大语言模型（LLM）是如何一步步“进化”出解决复杂问题能力的。

1. **Standard Prompting（标准提示词）：** 也就是“一问一答”。遇到复杂问题（如数学计算、实时信息），模型容易“幻觉”或者瞎编。
2. **Chain of Thought, CoT（思维链）：** 我们在提示词中加入一句 *“请一步一步地思考”*。模型开始在内部进行逻辑推理（Thought），准确率大幅提升，但它**依然无法突破自身知识库的限制**（比如不知道今天的天气）。
3. **ReAct（Reason + Act）：** 突破了单一闭环。模型不仅被允许“思考（Thought）”，还被赋予了“行动（Action）”的权利去调用外部工具。工具返回真实世界的数据作为“观察（Observation）”，模型根据观察结果继续思考，直到得出结论。

### 第二步：设计“游戏规则” —— 核心 Prompt 编写

要让一个普通的 LLM 变成 Agent，第一步是给它定规矩。我们需要通过 System Prompt 强制模型按照特定的格式输出，这样我们的 Python 脚本才能用正则表达式去提取它想调用的工具。

这个格式通常被严格定义为：

- **Thought:** 思考当前该做什么
- **Action:** 决定调用什么工具
- **Action Input:** 给工具传什么参数

### 第三步：代码实战 —— 手写纯 Python ReAct 引擎

接下来，我们将不依赖任何第三方库，纯手写一个拥有“计算器”和“天气查询”能力的简单 Agent。

#### 1. 定义虚拟工具

这是 Agent 与外部世界交互的“手脚”。

Python

```python
# 虚拟工具箱
def get_weather(location: str) -> str:
    """模拟天气查询 API"""
    weather_db = {"北京": "晴朗，25°C", "上海": "下雨，18°C"}
    return weather_db.get(location, "抱歉，无法获取该城市天气。")

def calculate(expression: str) -> str:
    """模拟计算器"""
    try:
        # 注意：实际生产中 eval 有安全风险，这里仅为演示
        return str(eval(expression))
    except Exception:
        return "计算表达式有误，请检查。"

# 将工具注册到字典中，方便后续调用
available_tools = {
    "get_weather": get_weather,
    "calculate": calculate
}
```

#### 2. 定义系统提示词 (System Prompt)

这是 Agent 的“大脑说明书”。

Python

```python
system_prompt = """
你是一个全能的智能助手，你可以通过思考和调用外部工具来解决问题。
你有以下工具可用：
- get_weather: 查询指定城市的天气。输入应当是城市名，例如 "北京"。
- calculate: 进行数学计算。输入应当是数学表达式，例如 "100 / 3"。

回答用户问题时，请严格按照以下格式进行（可以循环多次）：
Question: 用户提出的问题
Thought: 针对问题，你当前需要思考和计划的内容
Action: 你决定调用的工具名称（必须是 get_weather 或 calculate 之一）
Action Input: 传给工具的具体参数
Observation: 工具执行后返回的结果

当你认为已经得到了足够的线索来回答问题时，请输出：
Thought: 我现在知道最终答案了
Final Answer: 最终回答给用户的内容
"""
```

#### 3. 编写核心 ReAct 循环 (The Engine)

这是整个 Agent 最核心的调度逻辑。由于这里无法直接调用真实的 API 密钥，我用一个伪代码函数 `llm_generate` 来代替真实大模型的 API 调用（你可以用 OpenAI、Gemini 或其他本地大模型的 API 替换它）。

Python

```python
import re

def llm_generate(prompt: str) -> str:
    """
    这里需要替换为你真实的大模型 API 调用代码。
    作用是：传入 prompt，返回大模型的文本回复。
    """
    pass 

def react_agent(question: str, max_steps: int = 5):
    # 1. 初始化对话上下文
    prompt = system_prompt + f"\nQuestion: {question}\n"
    print(f"🎯 任务开始: {question}\n" + "-"*40)
    
    # 2. 开启 ReAct 循环
    for step in range(max_steps):
        # 让大模型根据当前的 prompt 生成下一步的回复
        # 此时模型会输出 Thought, Action, 和 Action Input
        model_response = llm_generate(prompt)
        print(model_response)
        
        prompt += model_response + "\n" # 将模型的输出追加到历史记录中
        
        # 3. 检查模型是否输出了最终答案
        if "Final Answer:" in model_response:
            print("\n🎉 任务完成！")
            return
            
        # 4. 如果没有结束，则解析模型想要调用的工具
        # 使用正则表达式提取 Action 和 Action Input
        action_match = re.search(r"Action:\s*(.*)", model_response)
        action_input_match = re.search(r"Action Input:\s*(.*)", model_response)
        
        if action_match and action_input_match:
            action = action_match.group(1).strip()
            action_input = action_input_match.group(1).strip()
            
            # 5. 执行工具 (Observation 环节)
            if action in available_tools:
                print(f"\n[系统执行] 调用工具 {action}，参数: {action_input}")
                observation = available_tools[action](action_input)
            else:
                observation = f"工具 {action} 不存在。"
                
            print(f"[系统返回] 观察结果 (Observation): {observation}\n")
            
            # 6. 将真实世界的反馈 (Observation) 塞回给大模型，进入下一轮循环
            prompt += f"Observation: {observation}\n"
        else:
            # 如果模型没有输出标准格式，强制结束或提示
            print("\n⚠️ 模型的输出不符合格式规范，循环异常中断。")
            break

    print("\n❌ 达到最大思考步数，未能得出最终答案。")

# 运行测试示例
# react_agent("北京今天的天气怎么样？如果温度低于20度我就不出门了，请问我今天能出门吗？")
```

## 工具调用（Tool Use / Function Calling）

```python
import json
from openai import OpenAI

# 共享的基础 Python 函数
def get_weather(city: str) -> str:
    """获取指定城市的天气"""
    # 真实场景下这里会调用外部天气 API，此处用字典模拟
    weather_data = {"北京": "晴天, 25度", "上海": "下雨, 20度"}
    return weather_data.get(city, f"{city}的天气未知，默认 22度")

def calculate_math(expression: str) -> str:
    """计算数学表达式的结果"""
    try:
        # 注意：实际生产中直接用 eval 有安全风险，此处仅为演示
        return str(eval(expression))
    except Exception as e:
        return f"计算错误: {e}"

# 初始化客户端 (请替换为你的 API Key，如果用国内模型请修改 base_url)
client = OpenAI(
api_key="ollama_dummy_key",
base_url="http://localhost:11434/v1",)



# 核心：定义工具列表 (Function Signature)
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "查询指定城市的当前天气",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "城市名称，例如：北京, 上海"
                    }
                },
                "required": ["city"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "calculate_math",
            "description": "计算数学表达式的结果",
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {
                        "type": "string",
                        "description": "合法的数学表达式，例如：15 * 8, 100 / 4"
                    }
                },
                "required": ["expression"]
            }
        }
    }
]


# 1. 准备对话历史
messages = [
    {"role": "user", "content": "北京天气怎么样？顺便帮我算一下 15 * 8 等于几？"}
]

# 2. 第一次调用大模型：带上工具列表
response = client.chat.completions.create(
    model="qwen2", # 或 gpt-4o
    messages=messages,
    tools=tools,
    tool_choice="auto" # 让模型自己决定是否调用工具
)


response_message = response.choices[0].message
messages.append(response_message) # 将模型的回复加入历史记录

# 3. 检查模型是否要求调用工具
if response_message.tool_calls:
    print("🤖 模型说：我需要调用工具来回答这个问题！\n")
    
    # 建立一个名字到实际 Python 函数的映射表
    available_functions = {
        "get_weather": get_weather,
        "calculate_math": calculate_math
    }
    
    # 遍历模型请求调用的每一个工具（可能是多个）
    for tool_call in response_message.tool_calls:
        function_name = tool_call.function.name
        function_to_call = available_functions[function_name]
        
        # 解析模型传过来的参数
        function_args = json.loads(tool_call.function.arguments)
        print(f"🔧 正在本地执行函数: {function_name}({function_args})")
        
        # 本地执行函数
        if function_name == "get_weather":
            function_response = function_to_call(city=function_args.get("city"))
        elif function_name == "calculate_math":
            function_response = function_to_call(expression=function_args.get("expression"))
            
        print(f"✅ 执行结果: {function_response}\n")
            
        # 4. 将本地执行的结果追加到对话历史中，发还给模型
        messages.append(
            {
                "tool_call_id": tool_call.id,
                "role": "tool",
                "name": function_name,
                "content": function_response,
            }
        )
        
    # 5. 第二次调用大模型：模型结合工具运行结果，生成最终的人类语言回答
    second_response = client.chat.completions.create(
        model="qwen2",
        messages=messages
    )
    print("🤖 最终回答：")
    print(second_response.choices[0].message.content)
```

```python
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langchain.agents import create_tool_calling_agent, AgentExecutor
from langchain_core.prompts import ChatPromptTemplate
import os
from openai import OpenAI



# 1. 使用 @tool 装饰器封装工具（注意：注释非常重要，它是模型理解工具用途的依据）
@tool
def get_weather(city: str) -> str:
    """查询指定城市的当前天气。例如：北京、上海"""
    weather_data = {"北京": "晴天, 25度", "上海": "下雨, 20度"}
    return weather_data.get(city, f"{city}的天气未知，默认 22度")

@tool
def calculate_math(expression: str) -> str:
    """计算数学表达式的结果。例如输入: 15 * 8"""
    try:
        return str(eval(expression))
    except Exception as e:
        return f"计算错误: {e}"

tools = [get_weather, calculate_math]

# 2. 初始化大模型
llm = OpenAI(
api_key="ollama_dummy_key",
base_url="http://localhost:11434/v1",)

# 3. 创建 Agent 的系统提示词
prompt = ChatPromptTemplate.from_messages([
    ("system", "你是一个得力的智能助手，请合理使用工具来回答用户的问题。"),
    ("user", "{input}"),
    ("placeholder", "{agent_scratchpad}"), # 这是 Agent 用来记录中间步骤（比如调用了什么工具）的占位符
])

# 4. 将模型、工具、提示词绑定，创建 Agent
agent = create_tool_calling_agent(llm, tools, prompt)

# 5. 使用 AgentExecutor 运行（它会自动处理“调用工具 -> 获取结果 -> 再次思考”的循环）
agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True)

# 6. 测试运行
print("开始执行 LangChain Agent...\n")
result = agent_executor.invoke({"input": "北京天气怎么样？顺便帮我算一下 15 * 8 等于几？"})

print("\n🤖 最终回答：")
print(result["output"])
```

## 记忆（Memory）

解决 LLM 上下文长度限制，让 Agent 具备上下文连贯性和长期记忆。

#### 1. 短期记忆（Short-term Memory）：基于 Token 的滑动窗口

单纯截断字符会导致意思不完整，更科学的方法是基于 Token 数量进行滑动窗口截断。

**实现思路与代码**： 我们可以借助 OpenAI 的 `tiktoken` 库来计算 Token。

Python

```python
import tiktoken

class ShortTermMemory:
    def __init__(self, max_tokens=50):
        self.history = []
        self.max_tokens = max_tokens
        # 使用 gpt-3.5/4 的编码方式
        self.encoding = tiktoken.get_encoding("cl100k_base")

    def add_message(self, role, content):
        self.history.append({"role": role, "content": content})
        self._sliding_window()

    def _sliding_window(self):
        """滑动窗口截断，确保总 Token 数不超过阈值"""
        total_tokens = 0
        # 从最新消息往前推算
        for i in range(len(self.history) - 1, -1, -1):
            msg_tokens = len(self.encoding.encode(self.history[i]["content"]))
            if total_tokens + msg_tokens > self.max_tokens:
                # 丢弃更早的记忆
                self.history = self.history[i+1:]
                break
            total_tokens += msg_tokens

# 测试
memory = ShortTermMemory(max_tokens=20)
memory.add_message("user", "你好，我今天想学习 Agent。")
memory.add_message("assistant", "太好了，我们从记忆模块开始。")
memory.add_message("user", "什么是滑动窗口？")
print(memory.history) 
# 输出结果将只保留最近的对话，早期的会被剔除
```

#### 2. 长期记忆（Long-term Memory）：Embedding 与 ChromaDB 实战

长期记忆的本质是 RAG。我们将一段文本存入向量数据库，并进行近似最近邻（ANN）查询。

Python

```python
import chromadb

# 1. 初始化本地 Chroma 数据库
client = chromadb.Client()
collection = client.create_collection(name="agent_long_term_memory")

# 2. 存入记忆（ChromaDB 默认会使用轻量级模型进行 Embedding）
documents = [
    "我的名字叫小明，我是一名 AI 开发者。",
    "RAG 的全称是 Retrieval-Augmented Generation。",
    "我最喜欢的编程语言是 Python。"
]
collection.add(
    documents=documents,
    metadatas=[{"source": "profile"}, {"source": "concept"}, {"source": "profile"}],
    ids=["id1", "id2", "id3"]
)

# 3. 检索记忆（ANN 召回）
query_text = "关于我的个人信息有什么？"
results = collection.query(
    query_texts=[query_text],
    n_results=2 # 召回最相似的两条
)

print("召回结果：", results['documents'])
# 预期输出将会召回 "我的名字叫小明..." 和 "我最喜欢的编程语言是 Python..."
```

#### 1. 文本向量化（Embedding）的高维映射本质

- **文本特征**（如 BERT/OpenAI 提取）：提取的是词语在上下文中的共现关系和语义关联。模型将每个句子映射为一个高维实数向量空间（通常是 768 维或 1536 维）中的一个坐标点。

在这个空间中，判断两段长期记忆是否相关的底层数学逻辑是**余弦相似度（Cosine Similarity）**。它衡量的是两个高维向量夹角的余弦值，夹角越小，语义越相似：

![image-20260525133047725](C:\Users\Airex\AppData\Roaming\Typora\typora-user-images\image-20260525133047725.png)

#### 2. 近似最近邻检索（ANN）与 HNSW 算法

如果你的长期记忆库里有上百万条文本，每次提问都要用上面的公式遍历计算一遍相似度（KNN），速度会极其缓慢。因此，向量数据库使用了 **ANN（Approximate Nearest Neighbor）**，即牺牲微小的精度换取极速的检索。

目前最主流的 ANN 底层算法是 **HNSW（Hierarchical Navigable Small World，分层导航小世界）**。

- **检索过程**：它将向量构建成多层图结构。最上层只有极少数稀疏的节点（像大城市），底层是所有节点（像村镇）。检索时，先在最上层快速定位到大概区域（跨国飞行），然后逐层往下找（高铁 -> 汽车 -> 步行），直到在底层找到与你的 Query 距离最近的那个向量点。这就把 $O(N)$ 的遍历时间复杂度降到了 $O(\log N)$。

```python
class MemoryAgent:
    def __init__(self):
        # 挂载短期记忆模块 (来自方案一)
        self.short_memory = ShortTermMemory(max_tokens=100)
        # 挂载长期记忆数据库 (来自方案一)
        self.long_memory_db = collection 
        
    def _retrieve_long_term_memory(self, user_query):
        """从向量库中进行 ANN 检索获取长期记忆"""
        results = self.long_memory_db.query(
            query_texts=[user_query],
            n_results=1
        )
        if results['documents'] and results['documents'][0]:
            return results['documents'][0][0]
        return ""

    def chat(self, user_query):
        # 1. 触发长期记忆：根据当前问题去库里捞相关背景
        background_knowledge = self._retrieve_long_term_memory(user_query)
        
        # 2. 组装 Prompt：将长期记忆与用户的当前问题拼接
        enhanced_prompt = f"已知信息：{background_knowledge}\n用户问题：{user_query}"
        
        # 3. 记录到短期记忆：将拼装好的内容送入滑动窗口
        self.short_memory.add_message("user", enhanced_prompt)
        
        # 4. 模拟 LLM 思考过程（此处本应调用大模型 API，这里用打印代替）
        print("【Agent 接收到的完整上下文】:")
        for msg in self.short_memory.history:
            print(f"[{msg['role']}]: {msg['content']}")
            
        # 5. 生成回答并存入短期记忆
        response = f"根据 '{background_knowledge}'，我得出的回答是..."
        self.short_memory.add_message("assistant", response)
        
        return response

# 运行你的 MVP
agent = MemoryAgent()
print("\n--- 第一轮对话 ---")
agent.chat("关于我的个人信息有什么？")

print("\n--- 第二轮对话 ---")
agent.chat("刚才我问了什么？") # 测试短期记忆
```

##  LangChain 与 LangGraph

`接收提问 -> Agent思考 -> [路由判断] -> 若需工具则调用 -> Agent总结生成最终回答`。

```python
from typing import Annotated
from typing_extensions import TypedDict
from langchain_core.messages import HumanMessage
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition

# ==========================================
# 1. 定义状态 (State)
# ==========================================
class State(TypedDict):
    # 使用 add_messages 确保新消息是追加而非覆盖
    messages: Annotated[list, add_messages]


# ==========================================
# 2. 定义工具 (Tools)
# ==========================================
@tool
def search_weather(location: str) -> str:
    """查询指定城市的天气。"""
    # 模拟真实的天气 API 返回逻辑
    if "北京" in location:
        return f"{location} 现在的天气是晴天，气温 25°C。"
    elif "东京" in location:
        return f"{location} 现在的天气是阵雨，气温 22°C。"
    else:
        return f"{location} 的天气未知，请查阅天气预报。"

tools = [search_weather]


# ==========================================
# 3. 初始化模型并绑定工具 (Models)
# ==========================================
# 通过 Ollama 的 OpenAI 兼容接口调用本地模型
llm = ChatOpenAI(
    model="qwen2",
    api_key="ollama_dummy_key",
    base_url="http://localhost:11434/v1",
    temperature=0,
)

# 让大模型知道自己有哪些工具可用
llm_with_tools = llm.bind_tools(tools)


# ==========================================
# 4. 定义图节点 (Nodes)
# ==========================================
def agent_node(state: State):
    """思考节点：处理当前状态，调用 LLM 生成回复或工具调用请求"""
    response = llm_with_tools.invoke(state["messages"])
    return {"messages": [response]}

# 行动节点：LangGraph 内置的 ToolNode 会自动解析大模型的 tool_calls 并执行函数
tool_node = ToolNode(tools)


# ==========================================
# 5. 构建状态机与路由规则 (Graph & Edges)
# ==========================================
graph_builder = StateGraph(State)

# 注册节点
graph_builder.add_node("agent", agent_node)
graph_builder.add_node("tools", tool_node)

# 注册执行边：起点 -> Agent
graph_builder.add_edge(START, "agent")

# 条件路由：Agent执行完后，判断是否需要调用工具
# tools_condition 逻辑：有 tool_calls -> "tools" 节点；否则 -> END 节点
graph_builder.add_conditional_edges(
    "agent",
    tools_condition,
)

# 闭环：工具执行完后，把结果返回给 agent 进行最终总结
graph_builder.add_edge("tools", "agent")

# 编译成可执行的图
graph = graph_builder.compile()


# ==========================================
# 6. 运行与测试函数
# ==========================================
def run_agent(query: str):
    print(f"\n{'='*50}")
    print(f"👤 用户提问: {query}")
    print(f"{'='*50}")
    
    initial_state = {"messages": [HumanMessage(content=query)]}
    
    # stream_mode="updates" 会在每次节点更新状态时返回数据
    for event in graph.stream(initial_state, stream_mode="updates"):
        for node_name, node_state in event.items():
            print(f"📍 当前进入节点: [{node_name}]")
            
            # 获取该节点生成的最新消息
            latest_msg = node_state["messages"][-1]
            
            # 打印大模型的工具调用决策
            if hasattr(latest_msg, 'tool_calls') and latest_msg.tool_calls:
                print(f"   🛠️ 动作：准备调用工具 -> {latest_msg.tool_calls[0]['name']}")
                print(f"   📥 参数：{latest_msg.tool_calls[0]['args']}")
            # 打印纯文本内容（包含工具执行结果或最终回答）
            elif latest_msg.content:
                print(f"   💬 内容：{latest_msg.content}")

# ==========================================
# 主程序入口
# ==========================================
if __name__ == "__main__":
    print("🚀 LangGraph Agent 启动测试...\n")
    
    # 测试用例 1：不需要工具的常规对话（观察是否直接走向 END）
    run_agent("你好，请问你是谁？")
    
    # 测试用例 2：需要工具的复杂任务（观察 Agent -> Tools -> Agent 的完整路由）
    run_agent("帮我查一下东京今天的天气怎么样？")
```

## 多智能体协作机制

### 1. 顺序执行（Sequential / Pipeline）

这是最基础、也最常用的协作模式，类似于工厂的流水线作业。

- **运行逻辑**：任务单向流动。Agent A 完成工作后，将其输出作为 Agent B 的输入，Agent B 完成后再交给 Agent C，以此类推。
- **局限性**：缺乏反馈机制。如果下游的 Agent 发现上游做错了，它通常无法直接把任务“打回重做”（除非你在代码外部写了循环逻辑）。

### 2. 层级结构（Hierarchical）

- **运行逻辑**：必须存在一个“经理（Manager）”角色的 Agent。用户只把任务交给经理，经理由此进行任务拆解，委派给下属的专业 Agent 执行。下属做完后汇报给经理，经理审核确认无误后，再汇总交付给用户。
- **局限性**：
  - **单点故障风险**：经理 Agent 是整个系统的瓶颈。如果经理的逻辑推理能力差，它可能会把任务分错，或者盲目通过下属的错误报告。
  - **成本飙升**：经理需要不断阅读下属的报告并进行决策，Token 消耗非常大。

### 3. 群聊辩论（Group Chat / Conversational）

- **运行逻辑**：多个 Agent 被放进同一个“聊天室”里共享上下文。当一个 Agent 发言完毕后，系统（通常是由另一个大模型作为路由器）会根据当前聊天的语境，动态决定下一个应该由谁来发言，直到满足某个退出条件。
- **局限性**：
  - **极易失控**：如果提示词没写好，Agent 可能会陷入无限循环的“抬杠”，或者逐渐偏离最初的主题。
  - **Token 黑洞**：因为所有人都在一个聊天室，每一次发言都需要把前面的聊天记录带上，成本极高。

```python
from crewai import Agent, Task, Crew, Process, LLM

# 使用本地 Ollama 模型 (与 agent09.py 的 ChatOpenAI 配置等价)
# LangChain 写法: ChatOpenAI(model="qwen2", base_url="http://localhost:11434/v1", ...)
# CrewAI 需使用 LLM 类，model 前缀 ollama/ 会自动路由到本地服务
llm = LLM(
    model="ollama/qwen2",
    api_key="ollama_dummy_key",
    base_url="http://localhost:11434/v1",
    temperature=0,
)

# ==========================================
# 第一部分：定义 Agents (分配角色和背景故事)
# ==========================================

# 1. 编写代码的 Agent
coder = Agent(
    role='资深 Python 工程师',
    goal='根据用户需求，编写高效、健壮且优雅的 Python 代码',
    backstory='你是一位在硅谷顶级科技公司工作了 10 年的架构师，精通各种算法和设计模式。你写出的代码不仅能运行，而且具有极高的可读性。',
    verbose=True, # 开启日志，以便我们观察它的思考过程
    allow_delegation=False, # 专注写代码，不把任务指派给别人
    llm=llm,
)

# 2. 审查代码的 Agent
reviewer = Agent(
    role='高级代码审查员 (QA)',
    goal='审查 Coder 提交的代码，找出潜在的 Bug、性能瓶颈或不符合规范的地方，并给出最终优化后的代码',
    backstory='你是一个极度严谨的代码审查员，对代码质量有着极高的要求。你熟悉 PEP8 规范，并且擅长发现那些隐藏极深的逻辑错误。',
    verbose=True,
    allow_delegation=False,
    llm=llm,
)

# ==========================================
# 第二部分：定义 Tasks (分配具体任务)
# ==========================================

# 我们假设输入的需求是：“写一个 Python 函数，用于检查一个字符串是否为回文（忽略大小写和标点符号）”
programming_requirement = "写一个 Python 函数，用于检查一个字符串是否为回文（忽略大小写和空格、标点符号），并提供几个测试用例。"

# 1. 分配给 Coder 的任务
coding_task = Task(
    description=f'根据以下需求编写 Python 代码：\n需求：{programming_requirement}',
    expected_output='一段完整、包含注释的 Python 代码。',
    agent=coder
)

# 2. 分配给 Reviewer 的任务
# 注意：在顺序执行模式下，coding_task 的输出会自动作为 context 传递给这个任务。
review_task = Task(
    description='审查前一个任务生成的代码。检查逻辑漏洞、边界情况处理是否完善以及命名规范。',
    expected_output='一份简短的代码审查报告，以及经过你修改和优化后的最终完整 Python 代码。',
    agent=reviewer
)

# ==========================================
# 第三部分：组建团队并执行 (Crew)
# ==========================================

# 实例化 Crew，将代理和任务按照顺序组合
dev_crew = Crew(
    agents=[coder, reviewer],
    tasks=[coding_task, review_task],
    process=Process.sequential # 顺序执行：Task 1 完成后交给 Task 2
)

# 启动团队任务！
print("🚀 团队开始工作，请观察日志输出：\n")
result = dev_crew.kickoff()

# ==========================================
# 第四部分：查看最终结果
# ==========================================

print("==============================================")
print("🎯 最终交付成果：")
print("==============================================")
print(result)
```

```python
import os
from autogen import AssistantAgent, UserProxyAgent, GroupChat, GroupChatManager

# 1. 基础配置 (请替换为你自己的 API Key，如果是第三方中转 API，请添加 base_url)
# 例如：os.environ["OPENAI_API_KEY"] = "sk-xxxx..."
llm_config = {
    "config_list": [
        {
            "model": "gpt-4o", # 建议使用推理能力强的模型
            "api_key": os.environ.get("OPENAI_API_KEY") 
        }
    ],
    "temperature": 0.7,
}

# 2. 创建 Coder Agent (负责写代码)
coder = AssistantAgent(
    name="Coder",
    system_message="""你是一个资深 Python 开发工程师。
    你的任务是根据需求编写高质量、带有详细注释的代码。
    如果 Reviewer 指出代码有问题，请仔细阅读反馈，修改代码并重新输出完整的代码。
    """,
    llm_config=llm_config,
)

# 3. 创建 Reviewer Agent (负责代码审查)
reviewer = AssistantAgent(
    name="Reviewer",
    system_message="""你是一个极其严格的代码审查员（Code Reviewer）。
    你的任务是审查 Coder 提交的代码，重点检查：
    1. 逻辑是否正确？
    2. 是否处理了边界情况（Edge cases）？
    3. 代码是否符合 Pythonic 规范？
    如果发现问题，请明确指出缺陷，并要求 Coder 重写。
    如果代码非常完美，完全满足需求且没有任何潜在 bug，请仅回复 'TERMINATE' 结束流程。
    """,
    llm_config=llm_config,
)

# 4. 创建 User Proxy (作为任务的发布者)
user_proxy = UserProxyAgent(
    name="User",
    system_message="你是一个项目经理。你只负责提出初始需求，不参与编写和审查代码。",
    human_input_mode="NEVER", # 设置为 NEVER 意味着全自动运行，不需要人类中途介入输入
    max_consecutive_auto_reply=10, # 防止陷入死循环，最多自动回复 10 轮
    is_termination_msg=lambda x: "TERMINATE" in x.get("content", "").upper(), # 当收到 TERMINATE 时终止任务
)

# 5. 组建群聊 (Group Chat)
# 将三个 Agent 放入同一个聊天室，让 Manager 自动决定下一个发言者
groupchat = GroupChat(
    agents=[user_proxy, coder, reviewer],
    messages=[],
    max_round=12 # 限制群聊的最大总轮数
)
manager = GroupChatManager(groupchat=groupchat, llm_config=llm_config)

# 6. 发起任务！
task_description = """
请用 Python 写一个函数，用于判断一个字符串是否是回文字符串。
要求：
1. 忽略大小写。
2. 忽略所有空格和标点符号（如 'A man, a plan, a canal: Panama' 应该返回 True）。
3. 提供至少 3 个测试用例。
"""

print("🚀 任务开始：正在将需求分发给 Agent 团队...\n")
user_proxy.initiate_chat(
    manager,
    message=task_description
)
```

