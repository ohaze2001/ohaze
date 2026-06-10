---
name: brainstorming
description: Use before creative work in the ohaze ship flow to run BDD/needs-side discovery, produce a user-language feature brief, and terminate at brief approved.
---

# Brainstorming Feature Briefs (ohaze)

This skill owns `/ohaze:ship` Phase 1. It keeps the conversation in product and requirement language: pain, user, scenarios, visible outcome, boundaries, capability, and scope mode. It does not ask haze to review implementation detail.

The output of Phase 1 is an approved feature brief in conversation. This fork does **not** write a spec file, does **not** invoke `ohaze:writing-plans`, and does **not** recap a full technical design back to haze. `/ohaze:ship` Phase 1.5 writes the spec later.

<HARD-GATE>
Do NOT write code, scaffold files, write a spec, invoke writing-plans, or take implementation action in this skill. Stop only after the user has approved the feature brief and control has been handed back to `/ohaze:ship`.
</HARD-GATE>

## Conversation Rhythm

Ask one question at a time. Prefer multiple choice when it helps haze answer quickly, but use open-ended questions when the user’s language is still fuzzy.

The goal is a BDD-flavored brief:

- What pain or unmet need exists.
- Who triggers or uses the feature.
- Which user场景 matter.
- What visible result tells the user it worked.
- Which outcomes are explicitly out of scope.
- Which capability list the feature must satisfy.
- Which scope mode is being chosen.

## 7 Forcing-Question Hints

These are flexible hints, not a strict ordered checklist. The LLM decides order, omission, follow-up depth, and phrasing based on context. Do not force all seven if the answer is already clear; do follow up when the user’s answer would make the brief ambiguous.

| Category | Ask For |
|---|---|
| Pain | 具体痛在哪? Ask for a specific example, not a hypothetical. |
| Reframe push-back | "You asked for X, but it sounds like the need is Y. Confirm?" |
| User | Who uses/triggers/calls this, and in what situation? |
| Visible outcome | After using it, what does the user see or experience differently? |
| Out of scope | Which scenarios should explicitly not be handled? |
| Capability extraction | "It sounds like this must do 1/2/3/4/5. What is missing?" |
| Scope 4-modes | Recommend Expansion / Selective Expansion / Hold Scope / Reduction with a reason; haze approves or pushes back. |

## Scope Reflection

Before declaring the brief approved, propose exactly one scope mode and explain the reason in product language:

- **Expansion**: the stated need is too narrow and should include adjacent user-visible capability.
- **Selective Expansion**: add only the one or two adjacent capabilities needed for a coherent workflow.
- **Hold Scope**: the requested scope is coherent as-is.
- **Reduction**: remove part of the request to keep the first ship focused and testable.

Ask haze to approve or push back. Record the final mode in the brief.

## Feature Brief Template

When the conversation is clear, present the feature brief using this template. Keep it readable for haze.

```markdown
# <feature 名> — Feature Brief
> 给 haze 看。spec 在 docs/ohaze/specs/... 给 Codex 看,你不用看。

## 这是干嘛的
<一句话产品定位 — reframed 之后的,可能跟你最初说的不一样>

## 给谁用
<调用者/用户/触发者>

## 用户场景 (Scenarios)
### Scenario 1: <happy path 名>
- Given <初始状态>
- When <用户做的事>
- Then <看到的结果>

### Scenario 2: <边界>
### Scenario 3: <失败/恢复>

## "完成的样子" Checklist
- [ ] 能 ...
- [ ] 不能 ...
- [ ] 失败时能 ...

## 不做什么 (Out of Scope)
- ...

## Scope 决策
- **模式**: <Expansion | Selective Expansion | Hold Scope | Reduction>
- **理由**: <一句话>

## Claude 替你决定的关键技术方向 (Phase 1.5 后回填,事后扫一眼)
- <一句话每条,不同意 push back>
```

## Approval And Self-Review

After haze approves the brief, do a short inline self-review before terminal:

1. Placeholder scan: no `TBD`, empty scenario, or vague checklist item remains.
2. Scenario consistency: each "完成的样子" item maps to at least one scenario or visible result.
3. Scope consistency: out-of-scope items do not contradict the checklist.
4. Ambiguity check: if a user-visible behavior has two reasonable interpretations, ask one more single-point question.

Fix issues in conversation only. Do not write a separate review file.

## Terminal State

The terminal state is `brief approved`.

Say:

> "Brief approved. Handing back to /ohaze:ship Phase 2 — it will create worktree and write this brief + spec inside the worktree."

This "Handing back" is a return-from-subroutine signal, NOT an end-of-turn signal. Your next action in the same assistant turn belongs to `/ohaze:ship`, which proceeds through Phase 1.5 / 1.6 / 2. Do not wait for the user to type anything after approval.

The caller will:

- Generate the Phase 1.5 spec from the approved brief.
- Run the Phase 1.6 Codex spec audit.
- Create the worktree.
- Write both `docs/ohaze/briefs/<date>-<slug>-brief.md` and `docs/ohaze/specs/<date>-<slug>-design.md`.
- Invoke `ohaze:writing-plans`.

You do none of those steps inside this skill.

## Key Principles

- One question at a time.
- User and visible result before implementation detail.
- Multiple choice when it reduces friction.
- Flexible forcing hints, not a scripted interrogation.
- Product-language brief first; spec later.
- End only at `brief approved` and explicit handoff.

## Attribution

Forked from the `brainstorming` skill in [obra/superpowers](https://github.com/obra/superpowers) v5.1.0 by Jesse Vincent, used under MIT license. The ohaze fork keeps the one-question-at-a-time discipline and hard gate, but v2.1 moves Phase 1 to BDD/needs-side discovery and hands spec writing to `/ohaze:ship` Phase 1.5.
