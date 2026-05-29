---
layout: post
title: "Rebuilding Every Six Months? How to Build a Durable Foundation for Agent Systems"
date: 2026-05-22 16:00:00 +0800
lang: en
permalink: /en/posts/agent-foundation/
alternate_url: /posts/agent-foundation/
description: "Agent systems need to separate the fast-moving AI core from the stable, auditable, and governable engineering foundation underneath it."
tags:
  - Agent
  - OpenEvent
  - Event-driven
  - Log-first
---

In the last few years, Agent projects have appeared one after another, from early frameworks such as LangChain to the recent wave around OpenClaw. Under that momentum sits an uncomfortable fact: very few of these efforts have turned Agent architecture into reusable, general-purpose infrastructure.

Many teams still rebuild the same tool layer, state layer, communication layer, control layer, and runtime skeleton inside their own problem domain. Agent products move fast, but the engineering foundation that keeps them running often looks like temporary scaffolding that has to be torn down and rebuilt every few months.

## The Engineering Foundation Is What Falls Apart

There is no shortage of Agent products, runtimes, and orchestration frameworks. What is still rare is a solid, reusable infrastructure layer that can preserve this experience instead of forcing every project to start from zero.

This problem becomes obvious in engineering practice. Vibe coding has clearly increased generation speed by an order of magnitude, but the resulting implementation quality is still not something teams can fully rely on. The same failure modes keep showing up across projects: network jitter leaves tasks stuck or aborted, context is lost, and tool-call failures lack a reliable recovery path. As vibe coding becomes mainstream, human engineers can lose control over the quality of Agent code instead of gaining it.

Agent systems contain two very different classes of modules. One is the AI core: models, strategies, memory, and task decomposition. These are strongly shaped by model capability and need rapid iteration and constant experimentation. The other is engineering infrastructure: tool execution, file systems, messaging, permissions, audit trails, and human takeover points. These belong to deterministic engineering. They should be stable over time, clear at the boundary, and predictable in behavior. For most Agent products, the former is the differentiating layer, while the latter becomes a maintenance burden every team has to carry.

The root cause is that this field still lacks an infrastructure layer that is reused repeatedly, maintained over the long term, and accumulated by the community. Protocols such as MCP and A2A create useful agreement at local interfaces, but they are interfaces, not a motherboard. Even with protocol alignment, every Agent framework still has to rebuild adaptation, runtime cooperation, and state management. The ecosystem lacks a standard center: a collaboration foundation that can decouple Agent modules into independently maintained units while still giving them a stable way to connect and compose.

The value of such a shared foundation is not limited to engineering quality and development speed. More importantly, it gives people a firm handle on intelligent systems again. It creates a public contract for collaboration across teams and organizations, and it gives users and regulators verifiable deterministic guarantees.

When the lower-level infrastructure of intelligent systems becomes stable, open, and auditable, engineers are no longer anxious observers staring at a black box. They become governance participants with explicit intervention points. Deterministic engineering must carry that promise natively: every tool call leaves a tamper-resistant audit record, every state transition exposes an observable context boundary, and every autonomous decision chain reserves an entry point for human review and emergency stop. Under the foundation there is no magic, only contracts. The highest duty of infrastructure is to preserve the human baseline of auditability and shutdown control. That promise cannot be built separately by every system through its own vibe-coded foundation.

## Log-first

What mechanism should carry this auditable and governable deterministic promise? In most Agent systems today, the trace of model reasoning, tool-call parameters, permission context, and human takeover actions are scattered across multiple places. Some live only in an ephemeral conversation window. Some are mixed into vector caches. Some are printed to stdout. Others are written into isolated structured log files. When an Agent behaves unexpectedly, engineers often have to reconstruct the causal chain by hand across different media. Audit becomes after-the-fact forensics instead of a native system capability.

A natural idea is to borrow from write-ahead logging: record first, apply later. The log is the source of truth, and database files are materialized views of that log. If this idea is moved into the Agent foundation, every tool call, model decision, permission check, and human policy override must first be written to a durable event log with a global ordering identifier before it is allowed to affect system state. Observability then stops being a patch added after the fact. It becomes part of the system skeleton from day one.

Following that idea further, the center of architecture may need to move. We are used to organizing storage around session state or context windows, but what happens if an immutable log stream becomes the center and every module interacts with the outside world by appending to and consuming from that log? Stateful modules stop being isolated islands. They become materialized views over the same log stream. State is no longer a collection of disconnected snapshots, but different projections of a shared event history. Module collaboration no longer depends on direct API calls; it happens indirectly through events that are produced and consumed.

From there, the shared foundation should not be a particular runtime or protocol gateway. It should be a durable, immutable, globally ordered event log. Model inference, tool execution, permission checks, and human intervention all collaborate around this log. It is the system's memory and the handle people can hold. It is both the boundary that decouples modules and the place where the ecosystem can accumulate shared engineering experience. This kind of foundation may be the starting point for the Agent ecosystem to move from isolated projects toward collaborative construction.

## From Session-driven to Event-driven

A log stream gives the system a unified data layer, but true Agent autonomy also requires rethinking how the system runs. The session-driven pattern common in Agent systems is essentially a direct copy of the LLM product shape into the architecture layer. Large models expose conversational APIs, and ChatGPT reinforced that interaction model. The industry then started treating the session as the default Agent skeleton. That is acceptable for information retrieval, but Agent systems are about action. They need to sense the environment continuously, respond to asynchronous changes, and preserve state across cycles. Using a conversation loop to carry that requirement is an architectural mismatch.

Session-driven architecture uses human input as the heartbeat of the system and mixes the interaction boundary with the sensing boundary. When an Agent waits for input, it is effectively disconnected from the real environment. File-system changes, external callbacks, dependency migrations, and other signals cannot automatically cross the session wall. To compensate, systems fall back to polling or scheduled scans. This passive pull model is inefficient: polling interval becomes sensing latency, high frequency wastes resources, low frequency causes lag, and rapid consecutive changes can expose intermediate states or miss short windows. The Agent cannot build an accurate causal model of the environment and can only decide from an imprecise snapshot.

This architectural inertia comes from product shape leaking into the technical layer. Once the system is built around sessions, session input becomes the default clock. But in an Agent system that must continuously sense its environment, file changes, external callbacks, timed signals, and user questions are all state-change inputs. The core abstraction should therefore be events, not sessions. Every input source enters the log stream in the same immutable form, and the Agent advances by consuming and responding to events. The session becomes a view projected from the event stream, while the Agent turns from a question-answering loop into an autonomous system aligned with its environment.

The event-driven view preserves the conversational experience while releasing the system from the hard constraint of dialogue turns. When events become the shared language of the foundation, all state changes, including chat input, file changes, and external callbacks, enter the log with equal status. The Agent can stay accurately aligned with the environment. Conversation can still serve the product-level communication experience, but it is no longer the runtime center. Agent engineering can move from polished demos into complex real-world scenarios only when event-driven execution becomes the core abstraction.

## OpenEvent

Based on event-driven and log-first thinking, I started the OpenEvent project. It is not meant to become another end-to-end Agent product. It tries to provide a deterministic foundation: using the event stream as the shared source of truth so that tool execution, state management, communication, and audit governance all sit on the same immutable log.

Around this minimal deterministic center, I hope different Agent frameworks, toolchains, and runtimes can find a basis for collaboration. Engineering experience scattered across individual projects can then become reusable, auditable, and governable public infrastructure.

Project: [https://github.com/openevent2026/openevent.git](https://github.com/openevent2026/openevent.git)

The next post describes the key design of OpenEvent.
