# Prompt Guide

## User Prompt

You should use the user prompt to pass in the actual query for which you need an answer for. The user prompt will be used to kick off a real-time web search to make sure the answer has the latest and the most relevant information needed.

**Example of a user prompt**

```
What are the best sushi restaurants in the world currently?
```

# Web Search Models: General Prompting Guidelines

Our web search-powered models combine the capabilities of LLMs with real-time web searches. Understanding how they differ from traditional LLMs will help you craft more effective prompts.

## Best Practices for Prompting Web Search Models

<CardGroup cols={2}>
  <Card title="Be Specific and Contextual">
    Unlike traditional LLMs, our web search models require specificity to retrieve relevant search results. Adding just 2-3 extra words of context can dramatically improve performance.

    **Good Example**: "Explain recent advances in climate prediction models for urban planning"

    **Poor Example**: "Tell me about climate models"

  </Card>

  <Card title="Avoid Few-Shot Prompting">
    While few-shot prompting works well for traditional LLMs, it confuses web search models by triggering searches for your examples rather than your actual query.

    **Good Example**: "Summarize the current research on mRNA vaccine technology"

    **Poor Example**: "Here's an example of a good summary about vaccines: \[example text]. Now summarize the current research on mRNA vaccines."

  </Card>

  <Card title="Think Like a Web Search User">
    Craft prompts with search-friendly terms that would appear on relevant web pages. Consider how experts in the field would describe the topic online.

    **Good Example**: "Compare the energy efficiency ratings of heat pumps vs. traditional HVAC systems for residential use"

    **Poor Example**: "Tell me which home heating is better"

  </Card>

  <Card title="Provide Relevant Context">
    Include critical context to guide the web search toward the most relevant content, but keep prompts concise and focused.

    **Good Example**: "Explain the impact of the 2023 EU digital markets regulations on app store competition for small developers"

    **Poor Example**: "What are the rules for app stores?"

  </Card>
</CardGroup>

## Web Search Model Pitfalls to Avoid

<CardGroup cols={2}>
  <Card title="Overly Generic Questions">
    Generic prompts lead to scattered web search results and unfocused responses. Always narrow your scope.

    **Avoid**: "What's happening in AI?"

    **Instead**: "What are the three most significant commercial applications of generative AI in healthcare in the past year?"

  </Card>

  <Card title="Traditional LLM Techniques">
    Prompting strategies designed for traditional LLM often don't work well with web search models. Adapt your approach accordingly.

    **Avoid**: "Act as an expert chef and give me a recipe for sourdough bread. Start by explaining the history of sourdough, then list ingredients, then..."

    **Instead**: "What's a reliable sourdough bread recipe for beginners? Include ingredients and step-by-step instructions."

  </Card>

  <Card title="Complex Multi-Part Requests">
    Complex prompts with multiple unrelated questions can confuse the search component. Focus on one topic per query.

    **Avoid**: "Explain quantum computing, and also tell me about regenerative agriculture, and provide stock market predictions."

    **Instead**: "Explain quantum computing principles that might impact cryptography in the next decade."

  </Card>

  <Card title="Assuming Search Intent">
    Don't assume the model will search for what you intended without specific direction. Be explicit about exactly what information you need.

    **Avoid**: "Tell me about the latest developments."

    **Instead**: "What are the latest developments in offshore wind energy technology announced in the past 6 months?"

  </Card>
</CardGroup>

## Handling URLs and Source Information

<Warning>
  **Never ask for URLs or source links in your prompts.** The generative model cannot see the actual URLs from the web search, which means any URLs it provides in the response text are likely to be hallucinated and incorrect.
</Warning>

### The Right Way to Access Sources

URLs and source information are automatically returned in the `search_results` field of the API response. This field contains accurate information about the sources used, including:

- `title`: The title of the source page
- `url`: The actual URL of the source
- `date`: The publication date of the content

**Example of incorrect prompting:**

```
❌ BAD: "From the past 5 days, identify high-potential Canadian news stories...
For each item, include:
- A clear headline
- 1–2 sentence summary
- Include a link to a source"
```

**Example of correct prompting:**

```
✅ GOOD: "From the past 5 days, identify high-potential Canadian news stories...
For each item, include:
- A clear headline
- 1–2 sentence summary
- Why it matters from a thought-leadership perspective"

// Then parse URLs from the search_results field in the API response
```

### Why This Matters

The web search and language generation components work differently:

1. **Web Search Component**: Finds and retrieves content from specific URLs
2. **Language Generation Component**: Processes the retrieved content but doesn't have access to the original URLs
3. **API Response**: Provides both the generated text and the accurate source URLs separately

When you ask for URLs in your prompt, the language model will attempt to generate them based on patterns it has seen, but these will not be the actual URLs that were searched. Always use the `search_results` field for accurate source information.

## Preventing Hallucination in Search Results

<Warning>
  **LLMs are designed to be "helpful" and may attempt to provide answers even when they lack sufficient information.** This can lead to hallucinated or inaccurate responses, especially when asking about sources that Sonar cannot access.
</Warning>

### Understanding the Helpfulness Problem

Large Language Models are trained to be assistive and will often try to provide an answer even when they're not confident about the information. This tendency can be problematic when:

- You request information from sources that Sonar cannot access (e.g., LinkedIn posts, private documents, paywalled content)
- The search doesn't return relevant results for your specific query
- You ask for very recent information that may not be indexed yet

### Common Scenarios That Lead to Hallucination

**Inaccessible Sources:**

```
❌ PROBLEMATIC: "What did the CEO of XYZ company post on LinkedIn yesterday about their new product launch?"
```

_Sonar may not be able to access LinkedIn content, but the model might still attempt to provide an answer based on general knowledge or patterns._

**Overly Specific Recent Events:**

```
❌ PROBLEMATIC: "What was discussed in the closed-door meeting between Company A and Company B last week?"
```

_Private information that wouldn't be publicly searchable may still get a fabricated response._

### How to Prevent Hallucination

**Use Explicit Instructions:**
Include clear guidance in your prompts about what to do when information isn't available:

```
✅ GOOD: "Search for recent developments in quantum computing breakthroughs.
If you are not able to get search results or find relevant information,
please state that clearly rather than providing speculative information."
```

**Set Clear Boundaries:**

```
✅ GOOD: "Based on publicly available sources from the past week, what are the latest policy changes in Canadian healthcare?
If no recent information is found, please indicate that no recent updates were discovered."
```

**Request Source Transparency:**

```
✅ GOOD: "Find information about Tesla's latest earnings report.
Only provide information that you can verify from your search results,
and clearly state if certain details are not available."
```

### Best Practices for Reliable Results

<CardGroup cols={2}>
  <Card title="Be Explicit About Limitations">
    Always instruct the model to acknowledge when it cannot find information rather than guessing.

    **Example**: "If you cannot find reliable sources for this information, please say so explicitly."

  </Card>

  <Card title="Focus on Accessible Sources">
    Stick to information that is likely to be publicly indexed and searchable.

    **Avoid**: LinkedIn posts, private company documents, closed meetings
    **Prefer**: News articles, public reports, official announcements

  </Card>

  <Card title="Use Conditional Language">
    Frame requests with conditional statements that give the model permission to say "I don't know."

    **Example**: "If available, provide details about... Otherwise, indicate what information could not be found."

  </Card>

  <Card title="Verify with Multiple Queries">
    For critical information, consider breaking complex requests into smaller, more specific queries to verify consistency.

    **Strategy**: Ask the same question in different ways and compare results for consistency.

  </Card>
</CardGroup>

### Tips for Different Query Types

| Query Type              | Best Practices                                                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Factual Research**    | • Use specific questions • Use search domain filters for academic sources • Consider "high" search context size                      |
| **Creative Content**    | • Provide detailed style guidelines in system prompt • Specify tone, voice, and audience                                             |
| **Technical Questions** | • Include relevant technical context • Specify preferred programming language/framework • Use domain filters for documentation sites |
| **Analysis & Insights** | • Request step-by-step reasoning • Ask for specific metrics or criteria                                                              |
