"""Claude tool definitions for AI project intake and contractor interview.

INTAKE_TOOLS — used during project intake sessions:
  - create_trade_scope: create a trade scope after gathering project details
  - ask_clarifying_question: ask the GC a clarifying question

INTERVIEW_TOOLS — used during contractor interview sessions:
  - create_task: create a task for the trade scope after the interview

Tool schema properties match the Pydantic field names in TradeScopeCreate and TaskCreate
to ensure tool input validation against the same constraints.
"""

from typing import Any

INTAKE_TOOLS: list[dict[str, Any]] = [
    {
        "name": "create_trade_scope",
        "description": (
            "Create a trade scope for the project. Call once per trade after gathering "
            "all project details from the GC. Each call creates one trade scope with its "
            "name, color, and suggested execution order."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "trade_name": {
                    "type": "string",
                    "description": (
                        "Trade name — match from the company's trade catalog if possible "
                        "(e.g. 'Electrical', 'Plumbing', 'HVAC'). Use the exact catalog "
                        "name if a match exists."
                    ),
                },
                "trade_color": {
                    "type": "string",
                    "description": (
                        "Hex color code for visual distinction on the project board, "
                        "e.g. #4CAF50 (green), #2196F3 (blue), #FF9800 (orange). "
                        "Use distinct colors for different trades."
                    ),
                },
                "sort_order": {
                    "type": "integer",
                    "description": (
                        "Suggested execution order (0-indexed). Lower numbers execute first. "
                        "Use construction sequencing: demolition=0, structural=1, rough MEP=2, "
                        "insulation=3, drywall=4, finishes=5+."
                    ),
                },
            },
            "required": ["trade_name", "sort_order"],
        },
    },
    {
        "name": "ask_clarifying_question",
        "description": (
            "Ask the GC a clarifying question before generating trade scopes. "
            "Use when the project description is ambiguous about trades needed, "
            "project scope, timeline, or specific requirements. "
            "Ask one focused question at a time."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The clarifying question to ask the GC.",
                },
            },
            "required": ["question"],
        },
    },
]

INTERVIEW_TOOLS: list[dict[str, Any]] = [
    {
        "name": "create_task",
        "description": (
            "Create a task for this trade scope. Call once per task after the interview "
            "is complete. Each call creates one concrete work item with title, description, "
            "priority, estimated hours, execution order, and materials needed."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "maxLength": 300,
                    "description": "Clear, action-oriented task title (e.g. 'Install 200A main panel').",
                },
                "description": {
                    "type": "string",
                    "description": "Detailed description of what needs to be done, including specifications.",
                },
                "priority": {
                    "type": "string",
                    "enum": ["low", "medium", "high", "urgent"],
                    "description": (
                        "Task priority: urgent=safety/blocking, high=critical path, "
                        "medium=standard, low=nice-to-have."
                    ),
                },
                "estimated_hours": {
                    "type": "number",
                    "description": "Estimated labor hours to complete this task (e.g. 4.5).",
                },
                "sort_order": {
                    "type": "integer",
                    "description": (
                        "Execution order within this trade scope (0-indexed). "
                        "Tasks with lower sort_order execute first."
                    ),
                },
                "materials_needed": {
                    "type": "array",
                    "description": "List of materials required for this task.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Material name (e.g. '12/2 Romex wire')",
                            },
                            "quantity": {
                                "type": "number",
                                "description": "Amount needed",
                            },
                            "unit": {
                                "type": "string",
                                "description": "Unit of measure (e.g. 'feet', 'boxes', 'pieces')",
                            },
                        },
                    },
                },
            },
            "required": ["title", "sort_order"],
        },
    },
]
