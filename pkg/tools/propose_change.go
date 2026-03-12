package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// PendingProposal represents a proposed file change awaiting approval.
type PendingProposal struct {
	ID        string `json:"id"`
	File      string `json:"file"`      // relative path within workspace, e.g. "LESSONS.md"
	Content   string `json:"content"`   // full new content to write
	Mode      string `json:"mode"`      // "append" or "replace"
	Reason    string `json:"reason"`    // why the change is proposed
	Channel   string `json:"channel"`   // originating channel for reply
	ChatID    string `json:"chat_id"`   // originating chat ID for reply
	CreatedAt string `json:"created_at"`
}

// ProposeChangeTool lets the LLM propose a change to a workspace .md file.
// The change is saved as a pending proposal and the user is notified.
// The user must /approve or /reject it before the file is modified.
type ProposeChangeTool struct {
	workspace    string
	sendCallback SendCallback
}

func NewProposeChangeTool(workspace string) *ProposeChangeTool {
	return &ProposeChangeTool{workspace: workspace}
}

func (t *ProposeChangeTool) SetSendCallback(cb SendCallback) {
	t.sendCallback = cb
}

func (t *ProposeChangeTool) Name() string { return "propose_change" }

func (t *ProposeChangeTool) Description() string {
	return "Propose a change to a workspace .md file for user approval. " +
		"Use when you want to update LESSONS.md, MEMORY.md, or any workspace doc. " +
		"The user will receive a notification and must /approve or /reject the change."
}

func (t *ProposeChangeTool) Parameters() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"file": map[string]any{
				"type":        "string",
				"description": "Filename within workspace, e.g. 'LESSONS.md' or 'memory/MEMORY.md'",
			},
			"content": map[string]any{
				"type":        "string",
				"description": "The content to append or use as full replacement",
			},
			"mode": map[string]any{
				"type":        "string",
				"enum":        []string{"append", "replace"},
				"description": "'append' adds to end of file, 'replace' overwrites entire file",
			},
			"reason": map[string]any{
				"type":        "string",
				"description": "Brief explanation of why this change is proposed",
			},
		},
		"required": []string{"file", "content", "mode", "reason"},
	}
}

func (t *ProposeChangeTool) Execute(ctx context.Context, args map[string]any) *ToolResult {
	file, _ := args["file"].(string)
	content, _ := args["content"].(string)
	mode, _ := args["mode"].(string)
	reason, _ := args["reason"].(string)

	if file == "" || content == "" || mode == "" {
		return &ToolResult{ForLLM: "file, content, and mode are required", IsError: true}
	}
	if mode != "append" && mode != "replace" {
		return &ToolResult{ForLLM: "mode must be 'append' or 'replace'", IsError: true}
	}
	// Safety: only allow .md files, no path traversal
	if !strings.HasSuffix(file, ".md") {
		return &ToolResult{ForLLM: "only .md files are supported", IsError: true}
	}
	if strings.Contains(file, "..") {
		return &ToolResult{ForLLM: "invalid file path", IsError: true}
	}

	channel := ToolChannel(ctx)
	chatID := ToolChatID(ctx)

	id := time.Now().UTC().Format("20060102-1504")
	proposal := PendingProposal{
		ID:        id,
		File:      file,
		Content:   content,
		Mode:      mode,
		Reason:    reason,
		Channel:   channel,
		ChatID:    chatID,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}

	if err := savePendingProposal(t.workspace, proposal); err != nil {
		return &ToolResult{ForLLM: fmt.Sprintf("failed to save proposal: %v", err), IsError: true}
	}

	// Notify user
	if t.sendCallback != nil && channel != "" && chatID != "" {
		preview := content
		if len(preview) > 200 {
			preview = preview[:200] + "..."
		}
		msg := fmt.Sprintf(
			"📝 *Proposed change* (ID: `%s`)\n\n"+
				"*File:* `%s` (%s)\n"+
				"*Reason:* %s\n\n"+
				"*Preview:*\n```\n%s\n```\n\n"+
				"Reply `/approve %s` or `/reject %s`",
			id, file, mode, reason, preview, id, id,
		)
		_ = t.sendCallback(channel, chatID, msg)
	}

	return &ToolResult{
		ForLLM: fmt.Sprintf("Proposal %s saved. User has been notified to approve or reject.", id),
		Silent: true,
	}
}

// --- Pending proposal storage (workspace/pending/) ---

func pendingDir(workspace string) string {
	return filepath.Join(workspace, "pending")
}

func savePendingProposal(workspace string, p PendingProposal) error {
	dir := pendingDir(workspace)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(dir, p.ID+".json")
	return os.WriteFile(path, data, 0o600)
}

// LoadPendingProposals returns all pending proposals, sorted by ID (chronological).
func LoadPendingProposals(workspace string) ([]PendingProposal, error) {
	dir := pendingDir(workspace)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var proposals []PendingProposal
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			continue
		}
		var p PendingProposal
		if err := json.Unmarshal(data, &p); err != nil {
			continue
		}
		proposals = append(proposals, p)
	}
	return proposals, nil
}

// ApplyProposal applies a pending proposal to the workspace file and deletes the proposal.
func ApplyProposal(workspace string, id string) (string, error) {
	proposals, err := LoadPendingProposals(workspace)
	if err != nil {
		return "", err
	}
	for _, p := range proposals {
		if p.ID != id {
			continue
		}
		filePath := filepath.Join(workspace, p.File)
		// Ensure parent dir exists
		if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
			return "", fmt.Errorf("mkdir: %w", err)
		}
		if p.Mode == "append" {
			f, err := os.OpenFile(filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
			if err != nil {
				return "", fmt.Errorf("open: %w", err)
			}
			_, werr := f.WriteString(p.Content)
			f.Close()
			if werr != nil {
				return "", fmt.Errorf("write: %w", werr)
			}
		} else {
			if err := os.WriteFile(filePath, []byte(p.Content), 0o644); err != nil {
				return "", fmt.Errorf("write: %w", err)
			}
		}
		// Delete pending file
		_ = os.Remove(filepath.Join(pendingDir(workspace), id+".json"))
		return fmt.Sprintf("✅ Applied: `%s` (%s) — %s", p.File, p.Mode, p.Reason), nil
	}
	return "", fmt.Errorf("proposal %q not found", id)
}

// RejectProposal deletes a pending proposal without applying it.
func RejectProposal(workspace string, id string) (string, error) {
	path := filepath.Join(pendingDir(workspace), id+".json")
	if err := os.Remove(path); err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("proposal %q not found", id)
		}
		return "", err
	}
	return fmt.Sprintf("❌ Rejected proposal %s", id), nil
}

// FormatPendingList returns a human-readable list of pending proposals.
func FormatPendingList(workspace string) string {
	proposals, _ := LoadPendingProposals(workspace)
	if len(proposals) == 0 {
		return "No pending proposals."
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("%d pending proposal(s):\n\n", len(proposals)))
	for _, p := range proposals {
		sb.WriteString(fmt.Sprintf("• `%s` → `%s` (%s)\n  %s\n", p.ID, p.File, p.Mode, p.Reason))
	}
	sb.WriteString("\nUse `/approve <id>`, `/approve all`, `/reject <id>`, or `/reject all`.")
	return sb.String()
}
