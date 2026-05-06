---
## Markdown Frontmatter Metadata
title: "Plan {{## Template - YYYYMMDD}}" # {{RELEVANT_TITLE}}
description: # {{DESCRIPTION_aka_STRATEGY_TO_BE_EXECUTED}}

## Metadata Related to Github Repository Management
semantic_title: "{{TYPE(SCOPE):SUBJECT}}" # {{SEMANTIC_TITLE}} (e.g., feat(auth): add login endpoint)
tags: [plan, template] # {{RELEVANT_LABELS}} Github Repository Labels (e.g., plan, bugfix, feature, docs, refactor)
assignees: # {{ASSIGNEE_NAME}} (e.g., @github_username, ClaudeAI, etc.)
reviewers: # {{REVIEWER_NAME}} (e.g., @github_username, ClaudeAI, etc.)
approvers: # {{APPROVER_NAME}} (e.g., @github_username, ClaudeAI, etc.)
Branch: # {{BRANCH_NAME}} (e.g., main, develop, feat/new-feature, docs/update-readme)
Base Branch: # {{BASE_BRANCH_NAME}} (e.g., main, develop, plan25c1/config-refactor)
pull_request: # {{PR_NUMBER_OR_URL}} (if applicable)
pull_request: #(related PR number or URL)
issues: # [{{RELATED_ISSUE_URLS}}] (if applicable) (e.g., ["github.com/erikplachta/python-class-based-module-framework/issues/123"])
milestone: # [{{RELATED_MILESTONES}}] (e.g., )
release: # [{{RELATED_RELEASES}}] (e.g.: ['v1.0.0', 'v2.1.3'])
version: 0.0.3 # {{VERSION_NUMBER}} (e.g., 0.1.0, semantic versioning. Should match project version if applicable)

## Metadata Related to Planning and Execution
status: # {{CURRENT_STATUS}} (e.g., 🔲 Not Started, 🔨 In Progress, ✅ Completed, ⏳ Deferred, ❓ Pending Review, ❌ Canceled)
effort: # {{EFFORT_ESTIMATE}} (e.g., time estimates like 2h, 1d, 3d, 1w, tbd.)
priority: # {{PRIORITY_LEVEL}} (e.g., P0-Critical, P1-High, P2-Medium, P3-Low)
risk: # {{RISK_LEVEL}} (e.g., High, Medium, Low)
impact: # {{IMPACT_LEVEL}} (e.g., High, Medium, Low)

# Documentation of additional metadata for tracking and management
Created: # {{YYYY-MM-DD HH:mm:ss}}
Updated: # {{YYYY-MM-DD HH:mm:ss}}
Author: # {{AUTHOR_NAME}}
Co-Authors: # [{{CO_AUTHOR_1}}, {{CO_AUTHOR_2}}] (if any) (e.g., @github_username, ClaudeAI, Github Copilot, etc.)
changelog: #{{CHANGELOG_ENTRIES}}
---

<!-- AI INSTRUCTIONS:

## Key Points

- Replace all {{PLACEHOLDERS}} with actual content
- Update Status emoji as work progresses (see Status Legend below)
- Check acceptance criteria boxes when met
- Log decisions in Decisions Made section
- Keep Session State current after each action
- Update frontmatter Status when all phases complete

## Status Legend

| Symbol | Category       | Description                            |
| ------ | -------------- | -------------------------------------- |
| 🔲     | Not Started    | Not started yet                        |
| 🔨     | In Progress    | Currently in progress                  |
| ✅     | Completed      | Completed successfully                 |
| ⏳     | Deferred       | Deferred, postponed, or waiting        |
| ❓     | Pending Review | Pending review or approval             |
| ❌     | Canceled       | No longer relevant, was rejected, etc. |

-->

## Table of Contents

- [Session State](#session-state)
- [Problem Statement(s)](#problem-statements)
- [Decisions Made](#decisions-made)
- [Risk & Mitigation](#risk--mitigation)
- [Tasks](#tasks)
  - [Progress Tracking](#progress-tracking)
  - [Phased Implementation Steps](#phased-implementation-steps)
  - [End of Plan Strategies](#end-of-plan-strategies)
- [References](#references)

## Session State

| Field         | Value                          |
| ------------- | ------------------------------ |
| Last Action   | {{LAST_COMPLETED_ACTION}}      |
| Next Action   | {{NEXT_ACTION_TO_TAKE}}        |
| Current Phase | Phase # - {{PHASE_TOPIC_NAME}} |
| Blockers      | {{NONE_OR_DESCRIPTION}}        |

## Problem Statement(s)

Clearly define the problem(s) this plan aims to solve and what success looks like.

### Problem_1

- **User Story**: As a {{USER_TYPE}}, I want {{ACTION}} so that {{BENEFIT}}
- **Description**: {{DETAILED_PROBLEM_DESCRIPTION}}
- **Impact**: {{HOW_THIS_AFFECTS_USERS_OR_PRODUCT}}
- **Acceptance Criteria**:
  - [ ] {{CRITERION_1}}
  - [ ] {{CRITERION_2}}
  - [ ] {{CRITERION_3}}
- **Notes**:
  - {{ADDITIONAL_CONTEXT}}

### Out of Scope

- {{EXCLUDED_ITEM_1}}
- {{EXCLUDED_ITEM_2}}

---

## Decisions Made

| Decision       | Rationale | Related To          | Date Time               |
| -------------- | --------- | ------------------- | ----------------------- |
| {{DECISION_1}} | {{WHY}}   | {{RELATED_ITEM(S)}} | {{YYYY-MM-DD HH:mm:ss}} |

---

## Risk & Mitigation

Strategies for avoiding risk and mitigating issues if they arise.

### Risk & Mitigation Strategy

{{RISK_AND_MITIGATION_STRATEGY}}

### Rollback Plan

{{ROLLBACK_PLAN_DESCRIPTION}}

---

## Tasks

This section outlines the specific tasks needed to address the problem statement(s).

Content is broken down into 3 sections:

1. [Progress Tracking](#progress-tracking) - track overall progress of the plan.
2. [Phased Implementation Steps](#phased-implementation-steps) - detailed breakdown into phases for structured execution.
3. [End of Plan Strategies](#end-of-plan-strategies) - strategies required for all plans (testing, coverage, docs).

### Progress Tracking

Track progress to prevent drift and ensure clarity between User and AI collaborator.

#### [Phased Implementation Steps](#phased-implementation-steps) - Progress Tracker

| Title                          | Status | Description                   |
| ------------------------------ | ------ | ----------------------------- |
| [Phase 1](#phase-1-topic_name) | 🔲     | {{BRIEF_PHASE_1_DESCRIPTION}} |
| [Phase 2](#phase-2-topic_name) | 🔲     | {{BRIEF_PHASE_2_DESCRIPTION}} |

#### [End of Plan Strategies](#end-of-plan-strategies) - Progress Tracker

| Title                           | Status | Description                                                   |
| ------------------------------- | ------ | ------------------------------------------------------------- |
| [Testing](#testing)             | ⏳     | Testing meets or exceeds target: **Target**: #, **Actual**: # |
| [Coverage](#code-coverage)      | ⏳     | Full Coverage: **Target**: ##.##%, **Actual**: ##.##%         |
| [Documentation](#documentation) | ⏳     | Existing updated, new created & old deprecated.               |

---

## Phased Implementation Steps

Detailed breakdown of implementation steps into phases for structured execution.

### Phase 1: {{TOPIC_NAME}}

{{PHASE_1_DETAILS}}

**Done when**: {{COMPLETION_CRITERIA}}

### Phase 2: {{TOPIC_NAME}}

{{PHASE_2_DETAILS}}

**Done when**: {{COMPLETION_CRITERIA}}

---

## End of Plan Strategies

How to handle specific scenarios.

### Testing

{{TESTING_STRATEGY_REFERENCE_SUMMARY_AND_LINK_TO_REFERENCE_FILE}}

### Code Coverage

{{CODE_COVERAGE_STRATEGY_REFERENCE_SUMMARY_AND_LINK_TO_REFERENCE_FILE}}

### Documentation

{{DOCUMENTATION_STRATEGY_REFERENCE_SUMMARY_AND_LINK_TO_REFERENCE_FILE}}

---

## References

{{REFERENCES_AND_LINKS_TO_ADDITIONAL_RESOURCES_THAT_MAY_BE_HELPFUL}}
