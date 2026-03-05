sequenceDiagram
    participant User
    participant ChatPlatform
    participant ChannelAdapter
    participant MessageBus
    participant Agent
    participant LLMProvider
    participant SkillExecutor

    User->>+ChatPlatform: Sends a message
    ChatPlatform->>+ChannelAdapter: Forwards message (e.g., via webhook)

    ChannelAdapter->>ChannelAdapter: Converts platform message to InboundMessage
    ChannelAdapter->>-MessageBus: Publishes InboundMessage

    MessageBus->>+Agent: Delivers InboundMessage
    Agent->>+LLMProvider: Sends request for completion (with tools)
    LLMProvider-->>-Agent: Returns LLMResponse

    alt Simple Text Response
        Agent->>Agent: Formulates text reply from LLMResponse
        Agent->>-MessageBus: Publishes OutboundMessage with text content
    else Tool Call Required
        Agent->>Agent: Parses ToolCall from LLMResponse
        Agent->>+SkillExecutor: Executes tool/skill
        SkillExecutor-->>-Agent: Returns tool result
        Agent->>+LLMProvider: Sends new request with tool result
        LLMProvider-->>-Agent: Returns final LLMResponse with text
        Agent->>Agent: Formulates final reply
        Agent->>-MessageBus: Publishes OutboundMessage
    end

    MessageBus->>+ChannelAdapter: Delivers OutboundMessage
    ChannelAdapter->>ChannelAdapter: Converts OutboundMessage to platform-specific format
    ChannelAdapter->>-ChatPlatform: Sends reply via API
    ChatPlatform-->>-User: Displays reply to user
