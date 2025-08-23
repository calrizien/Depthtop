# Claude Code for large-scale PDF processing

Claude Code provides a powerful ecosystem for processing large volumes of PDFs through its sub-agent architecture and hook system, supporting documents up to 100 pages with full visual understanding capabilities. **The platform enables 90% faster processing through parallelization** while maintaining minimal context in the main conversation—a critical requirement for large-scale document workflows. This research reveals that successful implementation requires careful orchestration of sub-agents, strategic use of hooks, and understanding of specific architectural patterns designed for high-volume document processing.

The system's architecture centers on three core principles: **parallelization for speed**, **context isolation for reliability**, and **event-driven coordination for scalability**. Multi-agent PDF processing systems typically consume 15× more tokens than single-agent approaches but deliver proportional performance gains when properly configured.

## Setting up sub-agents for token-intensive tasks

Claude Code sub-agents operate as specialized AI assistants with **independent context windows** that prevent pollution of the main conversation. Each sub-agent is defined in markdown files stored in `.claude/agents/` (project-level) or `~/.claude/agents/` (user-level), with project agents taking precedence.

The configuration structure uses frontmatter to define agent properties:
```markdown
---
name: pdf-processor
description: Use proactively for PDF document analysis, data extraction, and content summarization
tools: Read, Write, Bash
---

You are a specialized PDF processing expert. When invoked:

1. Analyze the provided PDF document structure and content
2. Extract text, tables, charts, and visual elements
3. Identify key information and data patterns
4. Summarize findings with page references
5. Generate structured output formats as needed

Key practices:
- Reference specific pages using PDF page numbers
- Analyze both textual and visual content
- Handle charts, diagrams, and tables comprehensively
- Provide accurate data extraction with source attribution
```

**Sub-agents maintain their own 200K+ token context windows**, allowing them to process entire 100-page PDFs without affecting the main conversation. This isolation enables the main conversation to remain focused on orchestration while sub-agents handle the token-intensive processing work.

For optimal context management, implement **progressive summarization** where sub-agents compress their findings before passing results back. Store detailed extraction results in external systems and pass only lightweight references to maintain minimal context overhead in the orchestrating conversation.

## Parallelization strategies for multiple PDFs

Claude Code supports **concurrent execution of up to 10 sub-agents**, with the system processing tasks in batches. The most effective parallelization pattern follows Anthropic's production approach of using 3-5 sub-agents running simultaneously, which demonstrated **90.2% performance improvement** over single-agent systems.

The **fan-out/fan-in architecture** proves most effective for PDF processing:
```
Main Orchestrator → Parallel Batch Processing
├── SubAgent A: Process PDFs 1-25 (text extraction)
├── SubAgent B: Process PDFs 26-50 (text extraction)
├── SubAgent C: Process PDFs 51-75 (visual analysis)
└── SubAgent D: Process PDFs 76-100 (metadata extraction)
```

**Git worktrees enable true parallel execution** by providing separate working directories for each Claude instance. This approach prevents file conflicts when multiple agents process documents simultaneously. For enterprise deployments, integrate with Apache Kafka to create event-driven processing pipelines that scale horizontally.

Implement **dynamic batch sizing** based on document complexity. Simple text-heavy PDFs can be processed in larger batches (10-15 per agent), while complex documents with extensive visual content require smaller batches (3-5 per agent) to prevent context overflow.

## Working with PDFs up to 100 pages

Claude Code's PDF processing capabilities include **full visual understanding** for documents up to 100 pages or 32MB. Each PDF page consumes approximately 1,500-3,000 tokens for text extraction plus additional tokens for visual processing, as pages are converted to high-resolution images for analysis.

The platform supports three integration methods:
```json
// URL Reference (recommended for accessible documents)
{
  "messages": [{
    "role": "user",
    "content": [{
      "type": "document",
      "source": {
        "type": "url",
        "url": "https://example.com/document.pdf"
      }
    }, {
      "type": "text",
      "text": "Analyze this document"
    }]
  }]
}
```

**Amazon Bedrock users must enable citations** for full visual analysis capabilities. Without citations enabled, the system falls back to basic text extraction only, missing charts, diagrams, and other visual elements. This distinction is critical for financial reports or technical documents where visual elements contain essential information.

For optimal processing, **place PDFs before text in requests** and ensure documents use standard fonts with proper page orientation. Enable prompt caching when repeatedly analyzing the same documents to reduce token consumption and processing time.

## Using the @ symbol for agent coordination

The @ symbol serves multiple purposes in Claude Code's coordination system. **File references use @filename syntax** to provide specific context to agents, supporting tab completion for efficient navigation. While direct @agent-name mentioning isn't the primary invocation method, agents are selected through explicit requests or automatic matching based on task descriptions.

For **MCP (Model Context Protocol) tools**, the @ pattern appears as `mcp__<server>__<tool>`, enabling integration with external systems. When coordinating PDF processing workflows, use structured task descriptions rather than @ mentions:
```
"Use the pdf-processor sub-agent to analyze financial_report_2024.pdf"
```

The system's **intelligent agent selection** matches task requirements to agent capabilities defined in their description fields. This automatic routing reduces the need for explicit agent specification while ensuring appropriate specialization for each task.

## Architecting minimal-context systems

**Context engineering represents the cornerstone** of efficient large-scale PDF processing. The hub-and-spoke architecture minimizes main conversation overhead by maintaining orchestration logic centrally while distributing processing work to specialized sub-agents with isolated contexts.

Implement **Just-In-Time (JIT) context loading** where agents receive only necessary information when needed. The HANDOFF_TOKEN validation pattern ensures agents understand their specific tasks without requiring full conversation history. This approach prevents context drift and maintains processing efficiency across extended workflows.

**External artifact storage** plays a crucial role in context minimization. Sub-agents store processing results in filesystems or databases, passing only structured references back to the orchestrator:
```
Processing complete for batch_2024_Q3:
- Documents processed: 47
- Data extracted: /results/batch_2024_Q3/
- Summary report: /summaries/Q3_analysis.json
- Errors logged: /logs/batch_2024_Q3_errors.log
```

Use **CLAUDE.md files** to establish persistent context that spans sessions without cluttering conversation history. These files should contain processing patterns, extraction schemas, and domain-specific guidelines that sub-agents can reference without repeated specification.

## Technical documentation on hooks

Claude Code hooks provide **deterministic control points** throughout the processing lifecycle. Hooks are shell commands triggered at specific events, configured through settings files at project or user level.

The hook system includes five primary events:

**PreToolUse Hook** executes after Claude creates tool parameters but before execution. This hook can block dangerous operations or validate parameters:
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "python3 .claude/hooks/validate_pdf_output.py"
      }]
    }]
  }
}
```

**PostToolUse Hook** runs after successful tool completion, enabling result validation and automated formatting. **UserPromptSubmit Hook** intercepts user prompts before Claude processes them, allowing context injection for PDF processing workflows.

Hooks receive structured JSON input via stdin:
```json
{
  "session_id": "pdf_processing_session_123",
  "transcript_path": "/logs/session_123.json",
  "tool_name": "Write",
  "tool_input": {
    "path": "/results/extracted_data.json",
    "content": "..."
  }
}
```

**Exit code 2 from any hook blocks the associated action**, providing a safety mechanism for preventing incorrect processing or protecting sensitive data. Hooks can output JSON for sophisticated flow control, including continuation decisions and output suppression.

## Sub-agent patterns for independent processing

Successful PDF processing implementations utilize **specialized agent hierarchies**. The vanzan01/claude-code-sub-agent-collective demonstrates effective patterns with agents like:
- **document-parser**: Handles PDF structure analysis and text extraction
- **metadata-extractor**: Processes document properties and classifications
- **content-analyzer**: Performs semantic analysis and categorization
- **quality-validator**: Verifies processing accuracy and completeness

**Each agent operates with single-responsibility focus**, preventing task overlap and ensuring efficient resource utilization. Agents communicate through structured task handoffs rather than shared context, maintaining independence while coordinating results.

Implement **progressive enhancement patterns** where basic extraction agents complete initial processing before specialized agents perform detailed analysis. This approach allows early termination for simple documents while enabling deep analysis when required.

For complex workflows, use **hierarchical coordination** with top-level orchestrators managing mid-level coordinators, which in turn supervise worker agents. This structure scales effectively for processing hundreds of documents while maintaining clear responsibility boundaries.

## Memory and context management for large volumes

**Context window management represents the primary challenge** in large-scale PDF processing. Claude Pro provides 200K+ tokens (approximately 500 pages of text), while Enterprise plans offer 500K tokens. A single 90-page corporate report with charts and images can consume the entire standard context window.

Implement **aggressive context clearing** using the `/clear` command between processing phases. When approaching context limits, spawn fresh sub-agents with clean contexts while maintaining continuity through careful state handoffs. Store essential information in external systems rather than conversation history.

**Document chunking strategies** prove essential for processing large document sets. Split PDFs into logical sections under 100 pages each, process chunks in parallel, then aggregate results. This approach prevents context overflow while maintaining processing efficiency.

Use **session management features** like `claude --resume` with session IDs to maintain continuity across extended processing runs. Implement checkpointing at regular intervals to enable recovery from failures without losing progress.

## Limitations and architectural considerations

**Token consumption scales dramatically** with multi-agent systems, using approximately 15× more tokens than single-agent approaches. This economic reality requires careful consideration of task value versus processing costs. Claude Max subscriptions ($100-200/month) prove more cost-effective than pay-per-token pricing for sustained high-volume processing.

**Processing speed varies significantly** based on document complexity. Text-only extraction processes quickly (~1,000 tokens for 3 pages), while full visual understanding requires substantially more resources (~7,000 tokens for 3 pages). Plan processing pipelines accordingly, prioritizing visual analysis only when necessary.

The system currently processes tasks in batches rather than true streaming, with parallelism capped at 10 concurrent agents. **Batch completion blocking** means all tasks in a batch must complete before the next batch begins, creating potential bottlenecks for workflows with varying document complexity.

**PDF file referencing contains known bugs** (issue #1510) affecting the @path-to-pdf syntax. Implement workarounds using direct file paths or URL references until resolved. Additionally, connection pooling and retry logic prove essential for maintaining reliability during extended processing runs.

## Coordinating multiple sub-agents effectively

**The orchestrator-worker pattern** provides the most reliable coordination framework. Lead agents analyze incoming document batches, develop processing strategies, and spawn appropriate sub-agents. This approach mirrors Anthropic's production system, which achieved 90% performance improvements through intelligent work distribution.

Implement **effort scaling rules** to match agent deployment to task complexity:
- Simple extraction: 1 agent with basic tools
- Comparative analysis: 2-4 agents with specialized focus
- Complex research: 10+ agents with clear boundaries

**Quality gates between processing phases** ensure reliable outputs. Implement validation checkpoints where orchestrators verify sub-agent results before proceeding. This approach prevents error propagation while maintaining processing momentum.

Use **event-driven coordination** for asynchronous workflows. Sub-agents publish completion events that trigger subsequent processing stages, enabling flexible pipeline construction without rigid sequential dependencies. Apache Kafka integration provides enterprise-scale event management for production deployments.

**Rainbow deployments** enable gradual migration between agent versions without disrupting active workflows. This approach proves critical for maintaining service continuity during updates to processing logic or agent configurations.

## Conclusion

Claude Code's sub-agent architecture and hook system provide a robust foundation for large-scale PDF processing, combining powerful parallelization capabilities with sophisticated context management. Success requires careful attention to architectural patterns, particularly the orchestrator-worker model with isolated context windows and event-driven coordination.

The platform's ability to process 100-page documents with full visual understanding, combined with support for 10 concurrent sub-agents, enables processing workflows that achieve 90% performance improvements over single-agent systems. However, these benefits come with **15× higher token consumption**, requiring careful economic analysis and optimization strategies.

Key implementation priorities include establishing clear agent hierarchies, implementing progressive summarization to manage context efficiently, utilizing hooks for process control and validation, and designing event-driven architectures that scale horizontally. With proper configuration and architectural choices, Claude Code transforms PDF processing from a sequential bottleneck into a highly parallel, efficient workflow capable of handling enterprise-scale document volumes.