# OpenEvent Blog

这是 OpenEvent 的 GitHub Pages 双语技术博客，关键词是事件驱动、日志先行的 Agent 框架。站点源码位于 `openevent-blog` 仓库。

## 发布

推送到 GitHub 后，在仓库 `Settings > Pages` 中选择 `GitHub Actions` 作为发布来源。`.github/workflows/pages.yml` 会使用 GitHub Pages 官方 Jekyll 构建流程发布站点。

默认站点地址：

```text
https://openevent2026.github.io/openevent-blog/
```

英文入口：

```text
https://openevent2026.github.io/openevent-blog/en/
```

## 写作

新文章放在 `_posts/` 下，文件名使用 Jekyll 约定：

```text
YYYY-MM-DD-post-slug.md
```

每篇文章需要包含 front matter：

```yaml
---
layout: post
title: "文章标题"
date: 2026-05-22 16:00:00 +0800
description: "文章摘要"
tags:
  - Agent
  - OpenEvent
---
```

双语文章需要分别设置 `lang`、`permalink` 和 `alternate_url`：

```yaml
lang: zh-CN
permalink: /posts/example/
alternate_url: /en/posts/example/
```

英文版对应：

```yaml
lang: en
permalink: /en/posts/example/
alternate_url: /posts/example/
```

## 本地检查

首次本地构建前安装 Ruby、Bundler，然后安装依赖：

```bash
bundle install
```

运行结构检查：

```bash
make verify
```

运行 Jekyll 构建和本地服务：

```bash
make build
make serve
```

`make build` 会执行真实的 Jekyll 构建；如果本机没有 Ruby/Jekyll 依赖会直接失败，避免误以为已经完成构建。
