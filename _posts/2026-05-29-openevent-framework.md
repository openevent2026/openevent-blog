---
layout: post
title: "OpenEvent：事件驱动、日志先行的 Agent 框架"
date: 2026-05-29 16:54:00 +0800
lang: zh-CN
permalink: /posts/openevent-framework/
alternate_url: /en/posts/openevent-framework/
description: "OpenEvent 是一层面向 Agent 场景的多模块协作基座，以全局有序事件日志统一模块通信、恢复、审计和治理。"
tags:
  - Agent
  - OpenEvent
  - 事件驱动
  - 日志先行
  - 框架设计
---

![Agent 模块划分]({{ '/assets/images/agent-modules.png' | relative_url }})

上一篇我们讨论的是：为什么 Agent 系统需要一层稳定、可治理、可审计的事件中枢，以及为什么会话驱动难以承载复杂系统工程。这一篇将具体展开，如果真要建这样一个中枢，它应该长什么样；更重要的是，它应该拒绝长成什么样。

OpenEvent 的定位很明确：它是一层面向 Agent 场景的多模块协作基座，不试图做端到端的 Agent 产品。它不碰业务语义，不内嵌业务协议，也不替上层模块定义 schema。除了内置的系统广播协议外，其他协议都放在独立模块里，以可插拔方式按需接入。OpenEvent 想统一的只有一件事：模块协作时共同依赖的事件中枢。

更进一步说，它是一套云原生的事件基础设施：协议、存储、模块和运行时边界都可以独立部署、独立演进、独立验证、按需扩缩，避免重新长成一个难以拆分的单体系统。

## 核心概念
消息队列解决了"怎么传"，RPC 解决了"怎么调"，但多模块协作还需要回答四个更基础的问题：谁在行动、在哪里协作、按什么规则理解彼此、传递的最小事实单元长什么样。OpenEvent 没有直接照搬现成的消息队列概念，而是围绕这四个问题，抽象出四个核心对象。

### 谁在行动：Principal
Principal 是系统中的身份标识，可以代表用户、某个 Agent、某个独立模块进程，或者某个系统账号。OpenEvent 不关心这个身份背后的业务含义，只校验它是否与当前 token 绑定一致，并据此决定"能不能进这个 Channel、能不能写这条消息"。它是所有动作的起点。

### 在哪里协作：Channel
有了身份，下一步是确定"在哪里"发生协作。Channel 是一个带元数据和访问控制的局部协作域。每个 Channel 有自己的 channel_id、name、visibility、members，以及 protocol 标记该域内部遵循的约定。它定义的是一批事件在谁的参与下、在哪个范围内流动。和简单的消息分桶相比，Channel 更接近一个受控的协作场——Principal 必须先满足 Channel 的访问规则，才能参与其中的事件流转。

### 按什么规则理解：Protocol
进入同一个 Channel 的模块，必须知道彼此在说什么。Protocol 是贴在 Channel 上的一个标签，用来告诉接入方：这个 Channel 里的 payload 应该按哪套上层约定来解释。除了系统广播协议外，其他协议全部放在独立模块中以可插拔方式接入。OpenEvent 主体只保存这个标签，不做 schema 校验，也不要求所有模块都能识别所有协议。它标记的是一门"方言"，中枢并不因此掌握这门语言。

### 传递什么：Message
身份、场所、规则都确定后，真正流动的是 Message。它是 Channel 边界内最小的不可变事实单元，包含 seq、channel_id、principal 和 payload：seq 把它放进全局有序时间线，channel_id 指明它属于哪个协作域，principal 表明是谁发出的，payload 承载真正的业务内容。OpenEvent 的很多设计，最终都是围绕如何让 Message 被可靠写入、可控读取、准确追踪展开的。

### 四者的关系
这四个对象不是孤立的配置项，而是一套相互嵌套的关系：Principal 定义动作主体，Channel 划定协作边界并控制谁能进入，Protocol 是贴在边界上的语义标签，Message 则是沿着边界流动的事实载体。落到代码层面，就是：一个 principal 创建一个带 protocol 的 channel，然后相关的principal按照protocol往里面写入 message 以实现通信或记录状态变化。OpenEvent 想稳定下来的，正是这套主体、边界、约定与事实之间的关系。

## 全局顺序
很多系统都能传消息，但对 Agent 来说，"能传"远远不够。模型决策、工具执行、人工介入、外部回执、文件变化、定时任务——这些输入来源各异，如果各自散落在会话窗口、日志文件和内存状态里，系统就没有一个统一的事实坐标系来理解它们到底谁先谁后。另一个现实问题是，现在的 Agent 遇到网络抖动或人为中断，只能重新对齐环境，无法基于之前的断点继续任务。因为此前发生的事实没有按统一顺序持久化下来，恢复时根本找不到该从哪条记录接着处理。

OpenEvent 的做法很直接：所有消息进入系统后，落进一条从 1 开始连续递增的全局序列，每条消息拿到一个 seq。这个编号不是为了好看，而是让不同模块终于能围绕同一条时间线协作。某次人工指令在 seq 100，某次工具执行结果在 101，某次 Agent 决策又基于前面哪些已发生的事实——它们不再是一堆彼此隔离的快照，而是能被放回同一条序列上对照。

Agent 出问题，往往不是因为"不会思考"，而是因为事后很难还原"它到底依据了什么事实行动"。一旦所有模块共享同一条事件序列，工程师就能沿着事实链理解系统行为，审计、排错、恢复和人工介入才有明确的抓手。更进一步，当 Agent 进程崩溃或需要重启时，只要从指定 seq 重新消费事件日志，就能精确恢复到崩溃前的状态，而不必重新对齐环境或依赖易失的内存快照。对强调治理与可控性的系统来说，全局顺序既是协作对齐的参照，也是精确状态恢复的基础。

## 模块协作边界
全局顺序解决了谁先谁后的问题，但还没解决"这件事归谁管"的问题。如果所有消息都堆在同一条总线上，没有局部边界，不同模块的业务事件很快会搅在一起，排查时难以定位，新增功能时牵一发而动全身。

OpenEvent 在全局序列之上引入了 Channel。它不是简单的消息分组，而是一个带协议标签的局部协作域。每个 Channel 绑定一个 protocol，模块在这个边界内自行约定事件种类、payload 结构和演进节奏，OpenEvent 主体不介入这些语义解释。

这样，系统真正被统一的是顺序、访问控制、读写语义和传输骨架；真正被解耦的是各模块在各自 Channel 内部使用的业务语言。IM 走 im.v1，模型代理走 llm.v1，未来工具调用走 tool.v1——它们不需要被压扁成一套全局统一的 payload 模型。新增模块时，不必回头修改一个越来越臃肿的中心协议，直接开一个新的 Channel，挂上自己的协议标签即可，变化被限制在局部。

## 服务端不解释 payload
中心服务既然能见到所有消息，一个很自然的诱惑就是顺手把协议校验也接过来——字段约束、结构检查、动作语义，一并做掉。短期看确实更完整，长期看却是把所有模块的协议演进绑在了自己身上。IM 改一个字段要升级中心服务，模型代理换一套输出格式也要升级中心服务，中枢迟早变成新的阻塞点。

OpenEvent 直接回避这一步。服务端知道 protocol 标签的存在，但 payload 对它只是字节流，不做 schema 校验，也不理解业务语义。它只管顺序、权限、写入约束、读取语义和可追踪性；"这段内容到底是什么意思"留给上层模块自己解释。

业务协议变得快，基础设施变得慢。把协议解释权留在模块边界内，字段怎么增删、动作怎么表达、事件之间怎么关联，模块可以独立调整，不需要反过来牵动整个基础设施层一起发版。一个想长期稳定的事件中枢，克制比多做更重要。

## 会话放到协议层
前面说协议解释权留给模块，具体怎么落地，可以用 IM 模块来看。IM 是一个独立项目，基于 OpenEvent 实现了 im.v1 协议。在它自己的定义里，一个 IM 会话就是一条 protocol=im.v1 的 Channel，会话的静态信息——provider、session_id、session_type、members——放在 Channel 的 description 元数据里，不占用消息 payload。

真正不断追加到事件流里的，是三类动态事件：
- sync.record：IM 平台上真实发生了一条记录。由 IM 模块写入，data 里带 provider_message_id、msg_type、text、content_raw。它表达的是“平台上确实出现了这条消息”。
- send.request：业务模块想往 IM 平台发消息。由业务方写入，IM 模块消费。payload 里有 request_id、msg_type、content、idempotency_key。它表达的是动作请求，和平台侧的真实记录分开处理。
- send.result：发送动作执行得怎么样。由 IM 模块写回，prev_seq 指向对应的 send.request，payload 里带 status、provider_message_id、error_code。它表达的是"刚才那个请求成功了还是失败了"，并不表达"群里出现了什么新内容"。如果成功，平台后续会把真实消息回调回来，再由 IM 模块写成 sync.record。

假设某个业务模块想往飞书发一句“请审批 Alice”。它先往 im.v1 的 Channel 写一条 send.request；IM 模块订阅到后调用飞书 API；调用结束后回写 send.result；随后飞书平台产生真实聊天记录，IM 模块再同步为 sync.record。同一件事在事件流里被拆成三步：想发什么、发得怎么样、平台上最终发生了什么。

会话仍然存在，只是放到了协议层。OpenEvent 本体仍然不需要理解聊天业务，它只需要保证这几类消息都能按统一顺序进入同一个 Channel，并继续受同一套访问控制和读写语义约束。至于 im.v1 字段怎么长、动作和记录怎么关联，这些属于独立 IM 模块的职责，不属于 OpenEvent 主体的内建能力。

## 访问控制
OpenEvent 的访问控制直接嵌在事件骨架里，框架层面只回答最基础的三个问题：谁能读、谁能写、谁能管。更复杂的权限模型留给上层业务或网关自行扩展。

校验逻辑很直接：先确认“你是谁”，再判断“你对这个 Channel 能做什么”。身份靠 principal + token 确认，动作权限则落在 Channel 的 visibility 和 members 上。

Channel 目前分三种可见性：
- public：所有人可读可写，元信息对所有人可见；
- protected：所有人可读，只有成员可写；
- private：只有成员可读可写。

无论哪种可见性，增删成员、修改 Channel 元数据的管理权限都只归 creator。读写和管理是分开的，一个人可能能读能写，但改不了成员列表。

这套规则显然覆盖不了所有企业级场景，比如细粒度字段级权限、动态角色继承、临时授权等都没涉及。但对当前阶段来说，它提供了足够清晰的边界：规则少、行为可预期、接入成本低。如果后续真有更复杂的需求，更适合在模块层或网关层按需补充，避免把复杂度提前塞进基座。

## 轻量模块和 DEMO
骨架本身离可用还差得远。OpenEvent 主体只负责事件顺序和访问控制，真正让系统跑起来的是长在这套骨架上的确定性模块——把各 Agent 系统中重复出现的共性需求，抽象成可独立维护的组件。
目前已经实现的有三个。
IM 模块基于 im.v1 协议，提供 payload 编解码、发布辅助，以及面向飞书/Lark 点对点单聊的同步 worker。它把外部 IM 平台上的真实消息同步成 sync.record，消费业务侧写出的 send.request，调用平台 API 后写回 send.result。它不理解 Agent 的任务目标，也不关心模型怎么推理。
Model Proxy基于 llm.v1 协议，消费 infer.request，调用 OpenAI-compatible API，再把 infer.result 写回同一个模型 Channel。对 OpenEvent 主体来说，这只是一条请求事件和一条结果事件。模型服务可以替换，协议可以演进，但中枢和大部分模块不受影响。
Agent Demo则是把上述模块串起来的最小闭环。它提供了一个聊天机器人，以及一套尽量简单的运行脚本，用来快速体验整套架构。

这个 Demo 里，每个会话绑定三类 Channel：
- IM channel（protocol=im.v1）：承载用户输入、Agent 回复请求和 IM 发送结果；
- Model channel（protocol=llm.v1）：承载模型推理请求和结果；
- WAL channel（protocol=agent.wal.v1）：承载 Agent 在发起模型请求前写下的前置提交记录。

用户在 IM 里发来一条消息，IM syncer 先写入 sync.record。Agent 看到这条事实后，会先往 WAL channel 写一条 llm.request.prepare，记录这次要处理哪些用户消息、写入模型请求前上一条模型请求在哪里；随后才向 Model channel 写入 infer.request。model-proxy 调用模型 provider 后写入 infer.result；Agent 再把最终回复写成 IM channel 里的 send.request；IM syncer 发送到 IM 平台并写回 send.result。

这条链路看起来比“收到消息后直接调模型再回消息”多了几步，多出来的是可恢复、可审计、可解释的工程边界。Agent 崩溃在 WAL 之后、模型请求之前，可以根据 WAL 补发；模型请求发出但结果未回，可以从 Model channel 恢复；IM 发送请求已经写入但平台调用失败，可以沿着 send.result 排查。每一步都是事件，不再是散落在进程内存里的临时状态。

Demo 的真正价值不是聊天功能，而是验证 OpenEvent 的模块边界能否跑通真实的 Agent 闭环。IM、模型代理、Agent、查看面板各自独立维护，不通过私有 API 强绑定，只围绕同一条事件日志协作。换掉 IM 平台、换掉模型 provider、增强 Agent 策略，理论上都发生在各自模块内部，不需要把整个系统推倒重来。

- IM 模块：[https://github.com/openevent-official/openevent-modules-im.git](https://github.com/openevent-official/openevent-modules-im.git)
- Model Proxy：[https://github.com/openevent-official/openevent-modules-model-proxy.git](https://github.com/openevent-official/openevent-modules-model-proxy.git)
- Agent Demo：[https://github.com/openevent-official/openevent-agent-demo.git](https://github.com/openevent-official/openevent-agent-demo.git)

## 记录查询面板
![OpenEvent View]({{ '/assets/images/openevent-view.png' | relative_url }})

OpenEvent 还提供了一个独立的事件查询模块 OpenEvent View，专门用来审计和排查问题。

它和普通的日志页面目标不同。普通日志是单点输出，排查时需要在多个服务的日志文件之间来回 grep，再手动拼凑一条跨模块的因果链。openevent-view 则按全局 seq 组织视图，支持按 principal 和 Channel 过滤，并且会根据 payload 的 JSON 结构做更适合阅读的展示。

实际排查时，工程师要回答的往往不是"某一行日志说了什么"，而是"用户消息在哪个 seq 进入系统，Agent 何时准备发起模型请求，模型结果如何返回，IM 发送动作是否成功"。这些事件分散在不同的 Channel 里，单行孤立日志很难还原这条链路。openevent-view 把它们放在同一个查询视图里，按 seq 排好，因果一目了然。

项目地址：[https://github.com/openevent-official/openevent-view](https://github.com/openevent-official/openevent-view)

## 避免传统事件驱动架构缺陷
传统事件驱动架构中，一个服务发出事件后，下游什么时候处理完成是不确定的，中间会存在业务状态不一致的时间窗口；一个业务动作可能跨多个 topic、多个 broker、多个服务日志和多份本地状态；常见消息系统也往往只能保证单个分区、某个 key 或某个 topic 内部有序，跨分区、跨 topic 的全局顺序很难成立，从而导致顺序不清，排查问题困难。

OpenEvent 的取舍刚好相反：它把模块协作收敛到一条全局有序日志里，任何进入系统的消息都有连续递增的 seq。这相当于给系统提供了一个基于序号的逻辑时钟，所有基于这条队列的通信都可以用这个逻辑时钟对齐。对全异步的 Agent 场景来说，这比追求高吞吐更实际——Agent 的关键路径本来就经过模型推理，这已经是慢操作；单条全局有序队列通常不会是最先出现的瓶颈。

传统架构还容易长成一张网：A 发事件给 B，B 处理完发给 C 和 D，D 又触发 E，链路被拆散到一堆主题和消费者里。Agent 场景天然是另一种结构：行为围绕 Agent 决策展开，确定性模块围绕 Agent 提供能力。IM、模型代理、文件系统、工具执行器这些模块只做两件事——把外部事实写入日志，消费 Agent 或业务模块的动作请求并回写结果。它们之间几乎不需要互相通信，形成近似星形的结构。

星形结构的直接收益是排查成本下降。模块不互相私聊，事实都回到同一条日志；动作请求和结果留在各自的 Channel 里；Agent 的决策链可以沿着 seq 回放。事件风暴、环形触发、隐式依赖这些传统事件架构里的常见问题，也因此更容易被避免。

对于事件契约演化，OpenEvent 尽量把边界显式化。Channel + Protocol 定义了局部协作域：一个 Channel 说明消息在哪个边界内流动，一个 protocol 说明 payload 应该按哪套上层约定解释。im.v1、llm.v1、agent.wal.v1 可以各自演进；OpenEvent 主体只保存标签，不把所有业务字段塞进中心 schema。破坏性变化也不应该偷偷改字段，而应该进入新的协议版本。

所以，OpenEvent 的目标不止是“再做一个事件总线”。它试图修正传统事件驱动架构最容易失控的几个位置：让确定性模块尽量不互相通信，统一围绕 Agent 的决策链读写事实；把日志从分散变成集中有序，把一致性窗口变成明确的逻辑时钟，把契约从隐式变成 Channel 级显式，把恢复和审计从事后补丁变成事件骨架的一部分。

## 后续方向
OpenEvent 还在早期阶段。接下来整个架构会继续朝更清晰的云原生边界演进：可替换的后端实现、独立部署的协议模块、更明确的运行时管理，以及更适合容器化和分布式运维的方式。

短期内值得期待的方向包括：

- 工具调用；
- 更多 IM 平台的原生支持；
- 定时事件；
- 邮件；
- LogBased 文件系统，自动将文件变更事件同步到 OpenEvent。

这些能力都会以独立模块的形式存在，OpenEvent 主体保持骨架的简洁与稳定，所有具体能力都在外围按需生长。

Kubernetes 是把部署、调度、服务发现、扩缩容这些确定性问题沉淀成共同底座，从而成为云原生的基石。Agent 生态也需要类似的工程基座：模型和策略可以随便换，但事件、状态、权限、审计和模块协作不应该每个项目从零搭一遍。OpenEvent 要做的，就是 Agent 系统之下那层稳定、开放、可审计的基座。
