#

import requests
from .utils import KwargsInitializable, rprint, GET_ENV_VAR

class Tool(KwargsInitializable):
    def __init__(self, **kwargs):
        self.name = ""
        super().__init__(**kwargs)

    def get_function_definition(self, short: bool):
        raise NotImplementedError("To be implemented")

    def __call__(self, *args, **kwargs):
        raise NotImplementedError("To be implemented")

# --
# useful tools

class StopResult(dict):
    pass

class StopTool(Tool):
    def __init__(self, agent=None):
        super().__init__(name="stop")
        self.agent = agent

    def get_function_definition(self, short: bool):
        if short:
            return """- def stop(output: str, log: str) -> Dict:  # Finalize and formalize the answer when the task is complete."""
        else:
            return """- stop
```python
def stop(output: str, log: str) -> dict:
    \""" Finalize and formalize the answer when the task is complete.
    Args:
        output (str): The concise, well-formatted final answer to the task.
        log (str): Brief notes or reasoning about how the answer was determined.
    Returns:
        dict: A dictionary with the following structure:
            {
                'output': <str>  # The well-formatted answer, strictly following any specified output format.
                'log': <str>     # Additional notes, such as steps taken, issues encountered, or relevant context.
            }
    Examples:
        >>> answer = stop(output="Inter Miami", log="Task completed. The answer was found using official team sources.")
        >>> print(answer)
    \"""
```"""

    def __call__(self, output: str, log: str):
        ret = StopResult(output=output, log=log)
        if self.agent is not None:
            self.agent.put_final_result(ret)  # mark end and put final result
        return ret

class AskLLMTool(Tool):
    def __init__(self, llm=None):
        super().__init__(name="ask_llm")
        self.llm = llm

    def set_llm(self, llm):
        self.llm = llm

    def get_function_definition(self, short: bool):
        if short:
            return """- def ask_llm(query: str) -> str:  # Directly query the language model for tasks that do not require external tools."""
        else:
            return """- ask_llm
```python
def ask_llm(query: str) -> str:
    \""" Directly query the language model for tasks that do not require external tools.
    Args:
        query (str): The specific question or instruction for the LLM.
    Returns:
        str: The LLM's generated response.
    Notes:
        - Use this function for fact-based or reasoning tasks that can be answered without web search or external data.
        - Phrase the query clearly and specifically.
    Examples:
        >>> answer = ask_llm(query="What is the capital city of the USA?")
        >>> print(answer)
    \"""
```"""

    def __call__(self, query: str):
        messages = [{"role": "system", "content": "You are a helpful assistant. Answer the user's query with your internal knowledge. Ensure to follow the required output format if specified."}, {"role": "user", "content": query}]
        response = self.llm(messages)
        return response

class SimpleSearchTool(Tool):
    def __init__(self, target="", llm=None, max_results=7, list_enum=True, **kwargs):
        super().__init__(name="simple_web_search")
        self.llm = llm
        self.max_results = max_results
        self.list_enum = list_enum
        if not target:
            target = GET_ENV_VAR("SEARCH_BACKEND", df="DuckDuckGo")  # use which backend search engine
        rprint(f"Setup SimpleSearchTool with {target}")
        self.target = target
        if target == "DuckDuckGo":
            self.ddgs_params = kwargs.copy()
            self.ddgs_text_params = {
                "region": GET_ENV_VAR("DDG_REGION"),
                "safesearch": GET_ENV_VAR("DDG_SAFESEARCH"),
                "timelimit": GET_ENV_VAR("DDG_TIMELIMIT"),
            }
            self.ddgs_text_params = {k: v for k, v in self.ddgs_text_params.items() if v}
        elif target == "Google":
            self.google_params = {"key": GET_ENV_VAR("SEARCH_API_KEY"), "cx": GET_ENV_VAR("SEARCH_CSE_ID")}
        elif target == "SerpAPI":
            # SerpAPI-based Google Search (no extra dependency required; uses HTTP API)
            self.serpapi_params = {
                "api_key": GET_ENV_VAR("SERPAPI_API_KEY"),
                "engine": GET_ENV_VAR("SERPAPI_ENGINE", df="google"),
                "hl": GET_ENV_VAR("SERPAPI_HL", df="en"),
                "gl": GET_ENV_VAR("SERPAPI_GL", df="us"),
            }
            # allow overrides via kwargs
            self.serpapi_params.update({k: v for k, v in kwargs.items() if v is not None})
        else:
            raise ValueError(f"UNK search target = {target}")
        # --

    def set_llm(self, llm):
        self.llm = llm  # might be useful for formatting?

    def get_function_definition(self, short: bool):
            if short:
                return """- def simple_web_search(query: str) -> str:  # Perform a quick web search using a search engine for straightforward information needs."""
            else:
                return """- simple_web_search
```python
def simple_web_search(query: str) -> str:
    \""" Perform a quick web search using a search engine for straightforward information needs.
    Args:
        query (str): A simple, well-phrased search term or question.
    Returns:
        str: A string containing search results, including titles, URLs, and snippets.
    Notes:
        - Use for quick lookups or when you need up-to-date information.
        - Avoid complex or multi-step queries; keep the query simple and direct.
        - Do not use for tasks requiring deep reasoning or multi-source synthesis.
    Examples:
        >>> answer = simple_web_search(query="latest iPhone")
        >>> print(answer)
    \"""
```"""

    def __call__(self, query: str):
        target = self.target
        if target == "DuckDuckGo":
            try:
                from ddgs import DDGS  # new package name
            except ImportError:
                from duckduckgo_search import DDGS  # fallback for older installs
                rprint("Warning: duckduckgo_search is deprecated; please install 'ddgs' (pip install ddgs).")
            ddgs = DDGS(**self.ddgs_params)
            rprint(f"Query ddgs with: query={query}, region={self.ddgs_text_params.get('region')}, safesearch={self.ddgs_text_params.get('safesearch')}, timelimit={self.ddgs_text_params.get('timelimit')}, max_results={self.max_results}")
            results = ddgs.text(query, max_results=self.max_results, **self.ddgs_text_params)
            search_results = [{"title": _item.get("title"), "link": _item.get("href"), "content": _item.get("body")} for _item in results]
        elif target == "Google":
            url = "https://www.googleapis.com/customsearch/v1"
            params = self.google_params.copy()
            params.update({"q": query, "num": self.max_results})
            rprint(f"Query google-search with params={params}")
            response = requests.get(url, params=params)
            results = response.json()
            search_results = [{"title": _item["title"], "link": _item["link"], "content": _item["snippet"]} for _item in results.get("items", [])]
        elif target == "SerpAPI":
            url = "https://serpapi.com/search.json"
            params = self.serpapi_params.copy()
            params.update({"q": query, "num": self.max_results})
            rprint(f"Query serpapi-google with params={{'engine': {params.get('engine')}, 'hl': {params.get('hl')}, 'gl': {params.get('gl')}, 'num': {params.get('num')}}}")
            response = requests.get(url, params=params)
            results = response.json()
            items = results.get("organic_results", []) or results.get("news_results", []) or []
            search_results = [{"title": _item.get("title", ""), "link": _item.get("link") or _item.get("url", ""), "content": _item.get("snippet") or _item.get("content", "")} for _item in items]
        else:
            raise ValueError(f"UNK search target = {target}")
        # --
        if len(search_results) == 0:
            ret = "Search Results: No results found! Try a less restrictive/simpler query."
        elif self.list_enum:
            ret = "Search Results:\n" + "\n".join([f"({ii}) title={repr(vv['title'])}, link={repr(vv['link'])}, content={repr(vv['content'])}" for ii, vv in enumerate(search_results)])
        else:
            ret = "Search Results:\n" + "\n".join([f"- title={repr(vv['title'])}, link={repr(vv['link'])}, content={repr(vv['content'])}" for ii, vv in enumerate(search_results)])
        return ret
