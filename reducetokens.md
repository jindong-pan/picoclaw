That `top` output tells the whole story. Your Ollama process is pinned at **100% CPU** and using **1.2GB of RAM**. On an Inspiron 1545 (likely a Core 2 Duo), that is a massive workout.

The reason a simple "echo hello" causes this heavy load is that PicoClaw isn't just sending "echo hello" to the AI. It is sending a **massive instruction manual** every single time.

### 1. The "Hidden" Novel

When you type "echo hello," PicoClaw sends a prompt that looks more like this:

* **System Prompt:** "You are an autonomous agent. You must think step-by-step. You must format your output in a specific JSON structure..." (Hundreds of words).
* **Tool Definitions:** Remember those **13 tools** you saw in the logs? PicoClaw sends a detailed description for every single one of them (how to use `bash`, how to use `fetch`, etc.). This is often **2,000 to 4,000 characters** of text.
* **Your Message:** "...and also, the user said: 'echo hello'."

### 2. The "Pre-fill" Bottleneck

Your CPU hits 100% because of the **Prompt Processing (Pre-fill)** phase. Before the AI can even say "hello" back, it has to "digest" all those tool definitions.

On a modern GPU, this takes milliseconds. On an older laptop CPU:

1. The CPU has to calculate "Attention" scores for every word in that 2,000-word manual.
2. Since you don't have a dedicated AI chip, your RAM and CPU cache are working overtime just to move the model data around.
3. **This is why it takes minutes.** The AI is essentially reading a book before answering a one-sentence question.

### 3. Why it feels like it's "running forever"

If PicoClaw has a **5-second timeout** (like we saw in your `grep`), here is the "death loop" happening:

1. PicoClaw sends the request.
2. Ollama starts working (CPU 100%).
3. 5 seconds pass.
4. PicoClaw says "Too slow!" and **kills the connection.**
5. PicoClaw (or its retry logic) **sends the request again.**
6. Ollama starts over from zero.

This explains why Ollama stays at 100% CPU but never actually finishes.

---

### How to break the cycle

#### Step 1: Fix the Timeout (Crucial)

You MUST give your Inspiron time to finish that "reading" phase.
Open **`pkg/providers/openai_compat/provider.go`** and change line 22:

```go
// From:
defaultRequestTimeout = 30 * time.Second
// To:
defaultRequestTimeout = 300 * time.Second 

```

#### Step 2: Use a "Lighter" Model

If you aren't already, make sure you are using the **1.5b** version of Qwen, not the 7b.

```bash
ollama pull qwen2.5:1.5b

```

#### Step 3: Monitor the "Real" Prompt

If you want to see the "Novel" PicoClaw is sending, set a breakpoint here in Delve:

```text
# (dlv) b github.com/jindong-pan/picoclaw/pkg/providers/openai_compat.(*Provider).Completion
b github.com/jindong-pan/picoclaw/pkg/providers/openai_compat.(*Provider).Chat
(dlv) c
(dlv) p req.Messages

```

This will show you exactly how many thousands of words are being sent for that simple "hello."

**Would you like me to show you how to disable some of those 13 tools to make the "manual" shorter and faster for your CPU to read?**
