package agent

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/jindong-pan/picoclaw/pkg/bus"
	"github.com/jindong-pan/picoclaw/pkg/logger"
)

const (
	lessonsFilename = "LESSONS.md"
	pendingMarker   = "[PENDING]"
	approvedMarker  = "[APPROVED]"
	rejectedMarker  = "[REJECTED]"
)

// postMortemContext holds everything needed for async post-mortem analysis.
type postMortemContext struct {
	workspace   string
	channel     string
	chatID      string
	userMessage string
	iterations  int
	toolLog     []string
}

// triggerPostMortem is called when runAgentLoop hits max iterations with no answer.
// It runs async so it never blocks the response to the user.
func (al *AgentLoop) triggerPostMortem(ctx context.Context, opts processOptions, iterations int, toolLog []string) {
	if opts.Channel == "" || opts.Channel == "system" || opts.ChatID == "" {
		return
	}

	agent := al.registry.GetDefaultAgent()
	if agent == nil {
		return
	}

	pmc := postMortemContext{
		workspace:   agent.Workspace,
		channel:     opts.Channel,
		chatID:      opts.ChatID,
		userMessage: opts.UserMessage,
		iterations:  iterations,
		toolLog:     toolLog,
	}

	go func() {
		bgCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		lesson, err := analyzeFailure(bgCtx, pmc)
		if err != nil {
			logger.WarnCF("postmortem", "Failed to analyze failure", map[string]any{
				"error": err.Error(),
			})
			lesson = fmt.Sprintf(
				"Query: %q\nIterations: %d\nTools: %s\n(diagnosis unavailable: %v)",
				pmTruncate(pmc.userMessage, 100),
				pmc.iterations,
				strings.Join(pmc.toolLog, " → "),
				err,
			)
		}

		entryID := writePendingLesson(pmc.workspace, pmc.userMessage, lesson)
		if entryID == "" {
			return
		}

		notifyMsg := fmt.Sprintf(
			"⚠️ *Failure detected* (iteration limit reached)\n\n"+
				"*Query:* %s\n\n"+
				"*Proposed lesson:*\n%s\n\n"+
				"Reply `/approve %s` to save or `/reject %s` to discard.",
			pmTruncate(pmc.userMessage, 80),
			lesson,
			entryID,
			entryID,
		)

		al.bus.PublishOutbound(bgCtx, bus.OutboundMessage{
			Channel: pmc.channel,
			ChatID:  pmc.chatID,
			Content: notifyMsg,
		})

		logger.InfoCF("postmortem", "Post-mortem notification sent", map[string]any{
			"entry_id": entryID,
			"channel":  pmc.channel,
		})
	}()
}

// analyzeFailure uses summarize.sh in the workspace to diagnose the failure.
// Uses Gemini API key instead of burning OpenRouter quota.
func analyzeFailure(ctx context.Context, pmc postMortemContext) (string, error) {
	toolSummary := strings.Join(pmc.toolLog, " → ")
	if toolSummary == "" {
		toolSummary = "(no tools called)"
	}

	input := fmt.Sprintf(
		"An AI agent failed to answer this query after hitting its iteration limit.\n\n"+
			"Query: %q\n"+
			"Iterations used: %d\n"+
			"Tools called (in order): %s\n\n"+
			"In 2-3 sentences: explain why this likely failed and what the agent should do differently next time. Be specific and actionable.",
		pmTruncate(pmc.userMessage, 200),
		pmc.iterations,
		toolSummary,
	)

	scriptPath := filepath.Join(pmc.workspace, "summarize.sh")
	if _, err := os.Stat(scriptPath); err != nil {
		return "", fmt.Errorf("summarize.sh not found at %s", scriptPath)
	}

	cmd := exec.CommandContext(ctx, scriptPath, "-", "--length", "short", "--plain")
	cmd.Stdin = strings.NewReader(input)
	cmd.Dir = pmc.workspace

	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("summarize.sh failed: %w", err)
	}

	result := strings.TrimSpace(string(out))
	if result == "" {
		return "", fmt.Errorf("summarize.sh returned empty output")
	}

	return result, nil
}

// writePendingLesson appends a [PENDING] entry to LESSONS.md.
// Returns the entry ID (e.g. "20260314-0542") or empty string on failure.
func writePendingLesson(workspace, userMessage, lesson string) string {
	lessonsPath := filepath.Join(workspace, lessonsFilename)
	entryID := time.Now().UTC().Format("20060102-1504")

	entry := fmt.Sprintf(
		"\n## %s %s — %s\n%s\n",
		pendingMarker,
		entryID,
		pmTruncate(userMessage, 60),
		lesson,
	)

	f, err := os.OpenFile(lessonsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		logger.WarnCF("postmortem", "Failed to open LESSONS.md", map[string]any{
			"path":  lessonsPath,
			"error": err.Error(),
		})
		return ""
	}
	defer f.Close()

	if _, err := f.WriteString(entry); err != nil {
		logger.WarnCF("postmortem", "Failed to write LESSONS.md", map[string]any{
			"error": err.Error(),
		})
		return ""
	}

	logger.InfoCF("postmortem", "Wrote pending lesson", map[string]any{
		"entry_id": entryID,
		"path":     lessonsPath,
	})
	return entryID
}

// approveLessons promotes [PENDING] → [APPROVED] for the given entry ID or "all".
func approveLessons(workspace, entryID string) string {
	return updateLessonStatus(workspace, entryID, pendingMarker, approvedMarker)
}

// rejectLessons marks [PENDING] → [REJECTED] for the given entry ID or "all".
func rejectLessons(workspace, entryID string) string {
	return updateLessonStatus(workspace, entryID, pendingMarker, rejectedMarker)
}

func updateLessonStatus(workspace, entryID, from, to string) string {
	lessonsPath := filepath.Join(workspace, lessonsFilename)
	data, err := os.ReadFile(lessonsPath)
	if err != nil {
		return "No LESSONS.md found."
	}

	content := string(data)
	count := 0

	if entryID == "all" {
		lines := strings.Split(content, "\n")
		for i, line := range lines {
			if strings.Contains(line, from) {
				lines[i] = strings.ReplaceAll(line, from, to)
				count++
			}
		}
		content = strings.Join(lines, "\n")
	} else {
		search := from + " " + entryID
		replace := to + " " + entryID
		if strings.Contains(content, search) {
			content = strings.ReplaceAll(content, search, replace)
			count++
		}
	}

	if count == 0 {
		return fmt.Sprintf("No %s lesson found with ID %q.", strings.ToLower(strings.Trim(from, "[]")), entryID)
	}

	if err := os.WriteFile(lessonsPath, []byte(content), 0644); err != nil {
		return fmt.Sprintf("Failed to update LESSONS.md: %v", err)
	}

	action := "Approved"
	if to == rejectedMarker {
		action = "Rejected"
	}
	return fmt.Sprintf("%s %d lesson(s) (ID: %s).", action, count, entryID)
}

// listPendingLessons returns a formatted list of pending lessons.
func listPendingLessons(workspace string) string {
	lessonsPath := filepath.Join(workspace, lessonsFilename)
	data, err := os.ReadFile(lessonsPath)
	if err != nil {
		return "No LESSONS.md found."
	}

	var pending []string
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "## "+pendingMarker) {
			pending = append(pending, strings.TrimPrefix(line, "## "))
		}
	}

	if len(pending) == 0 {
		return "No pending lessons."
	}

	return "Pending lessons:\n" + strings.Join(pending, "\n") +
		"\n\nUse `/approve <id>`, `/approve all`, `/reject <id>`, or `/reject all`."
}

// pmTruncate truncates a string to max chars.
// Named pmTruncate to avoid conflict with any truncate function elsewhere in the package.
func pmTruncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "..."
}
