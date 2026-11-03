"""Call the official Blender Lab MCP server over MCP stdio.

Usage: python tools/blender_lab.py list
       python tools/blender_lab.py execute path/to/script.py
       python tools/blender_lab.py tool TOOL_NAME '{"argument": "value"}'
"""
import asyncio
import json
import os
from pathlib import Path
import sys
from datetime import timedelta
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    executable = Path(sys.executable).parent / 'blender-mcp'
    params = StdioServerParameters(command=str(executable), env=dict(os.environ))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write, read_timeout_seconds=timedelta(seconds=600)) as client:
            await client.initialize()
            if sys.argv[1] == 'list':
                response = await client.list_tools()
                print(json.dumps([{'name': t.name, 'inputSchema': t.inputSchema} for t in response.tools], indent=2))
            else:
                if sys.argv[1] == 'execute-cli':
                    tool = 'execute_blender_code_for_cli'
                    args = {'blend_file': str(Path(sys.argv[2]).resolve()), 'code': '__file__ = ' + repr(str(Path(sys.argv[3]).resolve())) + '\n' + Path(sys.argv[3]).read_text()}
                elif sys.argv[1] == 'execute':
                    tool = 'execute_blender_code'
                    args = {'code': '__file__ = ' + repr(str(Path(sys.argv[2]).resolve())) + '\n' + Path(sys.argv[2]).read_text()}
                else:
                    tool = sys.argv[2]
                    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
                response = await client.call_tool(tool, args)
                print(response.model_dump_json(indent=2))
                if response.isError:
                    raise SystemExit(1)
asyncio.run(main())
