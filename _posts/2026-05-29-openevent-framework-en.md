---
layout: post
title: "OpenEvent: An Event-driven, Log-first Agent Framework"
date: 2026-05-29 16:54:00 +0800
lang: en
permalink: /en/posts/openevent-framework/
alternate_url: /posts/openevent-framework/
description: "OpenEvent is a collaboration foundation for Agent modules, using a globally ordered event log to unify communication, recovery, auditability, and governance."
tags:
  - Agent
  - OpenEvent
  - Event-driven
  - Log-first
  - Framework design
---

![Agent module boundaries]({{ '/assets/images/agent-modules.png' | relative_url }})

The previous post discussed why Agent systems need a stable, governable, auditable event center, and why session-driven architecture does not carry complex system engineering well. This post goes into the concrete design: what such a center should look like, and just as importantly, what it should refuse to become.

OpenEvent has a clear position. It is a multi-module collaboration foundation for Agent scenarios, not an end-to-end Agent product. It does not define business semantics, embed business protocols, or define schemas for upper-layer modules. Except for the built-in system broadcast protocol, protocols live in independent modules and are plugged in as needed. OpenEvent tries to unify only one thing: the event center that modules share when they collaborate.

More specifically, it is cloud-native event infrastructure. Protocols, storage, modules, and runtime boundaries can be deployed, evolved, verified, and scaled independently, so the system does not grow back into a monolith that cannot be split apart.

## Core Concepts

To make the event center stable, the basic objects in the system must be clear. OpenEvent does not directly copy concepts from message queues or RPC. Instead, it abstracts four objects around the core problems of multi-module collaboration: actor identity, collaboration scope, communication protocol, and event details.

- Principal: A Principal is an identity in the system. It can represent a user, an Agent, an independent module process, or a system account. OpenEvent does not care what the identity means in business terms. It only uses that identity to perform deterministic send and receive actions.
- Channel: A Channel is a local collaboration domain with metadata. Each Channel has a channel_id, name, visibility, members, and a protocol label describing the convention used inside that collaboration domain. In other words, a Channel defines which events flow, among which participants, and within which scope. Compared with a simple message bucket, it is closer to an access-controlled collaboration space.
- Protocol: In OpenEvent, a Protocol is a label. Each label names a communication protocol built on OpenEvent and tells consumers which upper-layer convention should be used to interpret the payload in that Channel. Except for the system broadcast protocol at channel_id=0, protocols live in independent module projects and are plugged in as needed. OpenEvent stores the label only. It does not validate schemas, and it does not require every module to understand every protocol. The label names a language; the center does not therefore speak that language.
- Message: A Channel is the collaboration boundary. A Message is the smallest fact unit that flows inside that boundary. A Message contains seq, channel_id, principal, and payload. Each OpenEvent instance maintains an ordered queue. seq marks the message's position in the global queue, channel_id says which collaboration domain it belongs to, principal says who emitted it, and payload carries the actual business content. Much of OpenEvent's design is about making Message writes reliable, reads controlled, and traces accurate.

Put together, Principal defines the actor, Channel defines the boundary, Protocol defines the local interpretation convention, and Message carries the facts that move through the boundary. OpenEvent is trying to stabilize this relationship between actors, boundaries, conventions, and facts.

## Global Ordering

Many systems can deliver messages, but for Agents, "can deliver" is not enough. Model decisions, tool execution, human intervention, external receipts, file changes, and timers all arrive from different sources. If they are scattered across conversation windows, log files, and memory state, the system has no shared factual coordinate system for understanding what happened before what. There is also a practical recovery problem: when an Agent hits network jitter or is interrupted by a person, it often has to realign with the environment from scratch instead of continuing from the prior breakpoint. The previous facts were not persisted in one ordered sequence, so recovery has no precise record to resume from.

OpenEvent's answer is direct. After messages enter the system, they land in a globally increasing sequence that starts at 1, and each message receives a seq. The number is not decorative. It lets different modules collaborate around the same timeline. A human instruction at seq 100, a tool result at seq 101, and an Agent decision based on earlier facts are no longer isolated snapshots. They can be placed back onto one sequence and compared.

When an Agent goes wrong, the problem is often not that it "cannot think"; it is that engineers cannot reconstruct which facts it used to act. Once every module shares the same event sequence, engineers can follow the fact chain to understand behavior. Audit, debugging, recovery, and human intervention finally have a concrete handle. When an Agent process crashes or needs to restart, it can consume the event log again from a specified seq and restore state precisely, without realigning with the environment or depending on volatile memory snapshots. For systems that emphasize governance and control, global ordering is both a collaboration reference and the basis for precise state recovery.

## Module Collaboration Boundaries

Global ordering answers what happened before what, but it does not answer who owns which thing. If every message sits on the same bus without local boundaries, business events from different modules quickly mix together. Debugging becomes hard, and new features can pull the whole system into change.

OpenEvent introduces Channels on top of the global sequence. A Channel is not just a message group. It is a local collaboration domain with a protocol label. Each Channel binds to a protocol, and modules inside that boundary define their own event kinds, payload structure, and evolution pace. The OpenEvent core does not interpret those semantics.

This means the system unifies ordering, ACL, read-write semantics, and transport skeleton, while module-specific business languages remain decoupled inside their Channels. IM can use im.v1, the model proxy can use llm.v1, and future tool calls can use tool.v1. They do not need to be flattened into one global payload model. Adding a module does not require editing an increasingly bloated central protocol. Open a new Channel, attach the module's protocol label, and keep the change local.

## The Server Does Not Interpret Payloads

Because the central service can see every message, there is an obvious temptation to take over protocol validation too: field constraints, structure checks, action semantics, all in one place. In the short term that may look more complete. In the long term it binds every module's protocol evolution to the central service. If IM changes a field, the center must upgrade. If the model proxy changes an output format, the center must upgrade. The event center eventually becomes a new blocker.

OpenEvent avoids that path. The server knows a protocol label exists, but payload is just bytes to it. It does not validate schemas or understand business semantics. It handles ordering, permissions, write constraints, read semantics, and traceability. The question "what does this content mean?" is left to the upper-layer module.

Business protocols change quickly. Infrastructure should change slowly. Leaving protocol interpretation inside module boundaries lets fields, actions, and event relationships evolve independently without pulling the entire infrastructure layer into every release. For an event center that should stay stable for a long time, restraint matters more than doing more.

## Sessions Belong in the Protocol Layer

The IM module is a useful example of what this means in practice. IM is an independent project that implements the im.v1 protocol on top of OpenEvent. In its own definition, an IM session is a Channel with protocol=im.v1. Static session information such as provider, session_id, session_type, and members goes into Channel description metadata instead of message payload.

The event stream continuously receives three kinds of dynamic events:

- sync.record: A real record occurred on the IM platform. The IM module writes it, and data includes provider_message_id, msg_type, text, and content_raw. It means that the platform really observed this message.
- send.request: A business module wants to send a message to the IM platform. The business side writes it and the IM module consumes it. The payload includes request_id, msg_type, content, and idempotency_key. It represents an action request and is handled separately from the platform's real record.
- send.result: The result of that send action. The IM module writes it back, prev_seq points to the corresponding send.request, and the payload contains status, provider_message_id, and error_code. It means whether the previous request succeeded or failed. It does not mean a new message has appeared in the chat. If the send succeeds, the platform later emits the real chat record, which the IM module then writes as sync.record.

Suppose a business module wants to send "Please approve Alice" to Lark. It first writes a send.request to an im.v1 Channel. The IM module subscribes to it and calls the Lark API. After the API call, it writes send.result. Then the Lark platform produces the real chat record, and the IM module syncs it as sync.record. One action is split into three facts in the event stream: what the system wanted to send, how the send action ended, and what finally happened on the platform.

The session still exists; it has moved into the protocol layer. The OpenEvent core does not need to understand chat business. It only guarantees that these messages enter the same Channel in a unified order and remain governed by the same ACL and read-write semantics. The shape of im.v1 fields and the relationship between actions and records belong to the independent IM module, not to built-in OpenEvent capability.

## Access Control

OpenEvent embeds access control directly in the event skeleton. At the framework layer, it answers only three basic questions: who can read, who can write, and who can administer. More complex permission models are left to upper-layer business logic or gateways.

The logic is simple: first confirm "who are you", then decide "what can you do to this Channel". Identity is confirmed by principal + token. Action permissions come from Channel visibility and members.

Channels currently have three visibility modes:

- public: everyone can read and write, and metadata is visible to everyone;
- protected: everyone can read, but only members can write;
- private: only members can read and write.

For all visibility modes, adding or removing members and changing Channel metadata is reserved for the creator. Reading, writing, and administration are separate. A user may be able to read and write without being able to change the member list.

This rule set does not cover every enterprise scenario. Field-level permissions, dynamic role inheritance, and temporary grants are not included. At the current stage, it provides a clear enough boundary: few rules, predictable behavior, and low integration cost. If more complex requirements appear later, they fit better in the module layer or gateway layer instead of being pushed into the foundation too early.

## Lightweight Modules and Demo

The skeleton alone is not enough to make the system useful. The OpenEvent core only owns event ordering and access control. What makes the system run are deterministic modules built on top of that skeleton: independently maintained components extracted from recurring needs in Agent systems.

Three modules are already implemented.

The IM module implements the im.v1 protocol. It provides payload encoding and decoding, publishing helpers, and a sync worker for Feishu/Lark one-to-one chats. It turns real external IM messages into sync.record, consumes send.request from business modules, calls the platform API, and writes send.result. It does not understand the Agent's task goal or how the model reasons.

Model Proxy implements the llm.v1 protocol. It consumes infer.request, calls an OpenAI-compatible API, and writes infer.result back to the same model Channel. To the OpenEvent core, this is just one request event and one result event. The model service can be replaced and the protocol can evolve without disturbing the center and most modules.

Agent Demo wires these modules into a minimal closed loop. It provides a chatbot and a deliberately simple set of scripts for quickly trying the architecture.

In this Demo, each session binds three kinds of Channels:

- IM channel (protocol=im.v1): carries user input, Agent reply requests, and IM send results;
- Model channel (protocol=llm.v1): carries model inference requests and results;
- WAL channel (protocol=agent.wal.v1): carries the pre-commit records the Agent writes before creating model requests.

When a user sends a message in IM, the IM syncer first writes sync.record. After the Agent sees that fact, it writes llm.request.prepare to the WAL channel, recording which user messages it is processing and where the previous model request was. Only then does it write infer.request to the Model channel. model-proxy calls the model provider and writes infer.result. The Agent then writes the final reply as send.request in the IM channel. The IM syncer sends it to the IM platform and writes send.result.

This path looks longer than "receive a message, call the model, reply". The extra steps are the recoverable, auditable, explainable engineering boundaries. If the Agent crashes after WAL but before the model request, WAL can drive a retry. If the model request was sent but no result returned, recovery can happen from the Model channel. If an IM send request was written but the platform call failed, send.result gives a clear path for diagnosis. Every step is an event, not temporary state scattered in process memory.

The Demo's value is not the chat function itself. Its value is proving that OpenEvent's module boundaries can support a real Agent loop. IM, model proxy, Agent, and view panel are independently maintained. They are not tied together through private APIs; they collaborate around the same event log. Replacing the IM platform, replacing the model provider, or improving the Agent strategy should happen inside each module rather than requiring the whole system to be rebuilt.

- IM module: [https://github.com/openevent2026/openevent-modules-im.git](https://github.com/openevent2026/openevent-modules-im.git)
- Model Proxy: [https://github.com/openevent2026/openevent-modules-model-proxy.git](https://github.com/openevent2026/openevent-modules-model-proxy.git)
- Agent Demo: [https://github.com/openevent2026/openevent-agent-demo.git](https://github.com/openevent2026/openevent-agent-demo.git)

## Event Query Panel

![OpenEvent View]({{ '/assets/images/openevent-view.png' | relative_url }})

OpenEvent also provides an independent event query module, OpenEvent View, for audit and debugging.

Its goal is different from an ordinary log page. Ordinary logs are point outputs. Debugging requires grepping across log files from several services and manually piecing together a cross-module causal chain. openevent-view organizes the view by global seq, supports filtering by principal and Channel, and renders JSON payloads in a more readable way.

In real debugging, engineers often need to answer questions such as: at which seq did the user message enter the system, when did the Agent prepare the model request, how did the model result return, and did the IM send action succeed? These events are spread across different Channels, and isolated log lines make the chain hard to reconstruct. openevent-view places them in one query view ordered by seq, making causality visible.

Project: [https://github.com/openevent2026/openevent-view](https://github.com/openevent2026/openevent-view)

## Avoiding Traditional Event-driven Architecture Failure Modes

In traditional event-driven architecture, after one service emits an event, the time when downstream processing completes is uncertain. A business action can pass through multiple topics, brokers, service logs, and local states. Common message systems often guarantee ordering only within one partition, one key, or one topic. Global order across partitions and topics is hard to obtain, which makes ordering unclear and debugging difficult.

OpenEvent makes the opposite tradeoff. It narrows module collaboration into one globally ordered log, and every message that enters the system receives a continuously increasing seq. This gives the system a sequence-based logical clock. All communication over the queue can align against that logical clock. For fully asynchronous Agent scenarios, this is more practical than maximizing throughput. The Agent critical path already goes through model inference, which is slow; a single globally ordered queue is usually not the first bottleneck.

Traditional architectures also tend to become a web. A sends an event to B, B triggers C and D, D triggers E, and the chain is scattered across many topics and consumers. Agent scenarios naturally fit another shape. Behavior revolves around Agent decisions, and deterministic modules provide capabilities around the Agent. IM, model proxy, file system, and tool executor modules mostly do two things: write external facts to the log, and consume Agent or business action requests before writing results back. They rarely need to communicate with each other, forming a nearly star-shaped structure.

The immediate benefit is lower debugging cost. Modules do not privately talk to each other. Facts return to the same log. Action requests and results stay in their respective Channels. The Agent decision chain can be replayed along seq. Event storms, circular triggers, and implicit dependencies, common failure modes in traditional event-driven architecture, become easier to avoid.

For event contract evolution, OpenEvent tries to make boundaries explicit. Channel + Protocol defines a local collaboration domain: a Channel says where messages flow, and a protocol says which upper-layer convention should interpret the payload. im.v1, llm.v1, and agent.wal.v1 can evolve independently. The OpenEvent core stores labels only and does not put every business field into a central schema. Breaking changes should not silently mutate fields; they should move into a new protocol version.

OpenEvent is therefore not just "another event bus". It tries to correct several places where traditional event-driven architecture easily loses control: deterministic modules should avoid talking directly to each other and instead read and write facts around the Agent decision chain; logs should become centralized and ordered instead of scattered; consistency windows should become explicit logical clocks; contracts should move from implicit assumptions to Channel-level boundaries; and recovery and audit should become part of the event skeleton instead of patches added later.

## Next Directions

OpenEvent is still early. The architecture will continue moving toward clearer cloud-native boundaries: replaceable backend implementations, independently deployed protocol modules, clearer runtime management, and better support for containerized and distributed operations.

Short-term directions worth watching include:

- tool calls;
- native support for more IM platforms;
- scheduled events;
- email;
- a LogBased file system that automatically syncs file-change events to OpenEvent.

These capabilities will exist as independent modules. The OpenEvent core will keep the skeleton simple and stable, while concrete capabilities grow around it as needed.

Kubernetes turned deterministic problems such as deployment, scheduling, service discovery, and scaling into a shared foundation, and that foundation became the base of cloud native. The Agent ecosystem needs a similar engineering foundation. Models and strategies can change freely, but events, state, permissions, auditability, and module collaboration should not be rebuilt from scratch in every project. OpenEvent is the stable, open, auditable foundation beneath Agent systems.
