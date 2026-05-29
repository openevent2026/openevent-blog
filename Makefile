.PHONY: build serve test verify clean

build:
	@if command -v bundle >/dev/null 2>&1; then \
		bundle exec jekyll build; \
	elif command -v jekyll >/dev/null 2>&1; then \
		jekyll build; \
	else \
		echo "Install Ruby, Bundler, and Jekyll dependencies before building locally."; \
		exit 1; \
	fi

serve:
	@if command -v bundle >/dev/null 2>&1; then \
		bundle exec jekyll serve --host 127.0.0.1; \
	elif command -v jekyll >/dev/null 2>&1; then \
		jekyll serve --host 127.0.0.1; \
	else \
		echo "Install Ruby, Bundler, and Jekyll to serve locally."; \
		exit 1; \
	fi

test: verify

verify:
	@test -f .github/workflows/pages.yml
	@test -f .gitignore
	@test -f Gemfile
	@test -f Gemfile.lock
	@test -f _config.yml
	@test -f index.html
	@test -f en/index.html
	@test -f about/index.html
	@test -f en/about/index.html
	@test -f archive/index.html
	@test -f en/archive/index.html
	@test -f 404.html
	@test -f robots.txt
	@test -f _layouts/default.html
	@test -f _layouts/post.html
	@test -f _includes/home.html
	@test -f _posts/2026-05-22-agent-foundation.md
	@test -f _posts/2026-05-22-agent-foundation-en.md
	@test -f _posts/2026-05-29-openevent-framework.md
	@test -f _posts/2026-05-29-openevent-framework-en.md
	@test -f assets/images/agent-modules.png
	@test -f assets/images/openevent-view.png
	@test -f assets/images/favicon.svg
	@grep -q 'actions/jekyll-build-pages' .github/workflows/pages.yml
	@grep -q 'github-pages' Gemfile
	@grep -q '^layout: post' _posts/2026-05-22-agent-foundation.md
	@grep -q '^lang: zh-CN' _posts/2026-05-22-agent-foundation.md
	@grep -q '^lang: en' _posts/2026-05-22-agent-foundation-en.md
	@grep -q 'OpenEvent：事件驱动、日志先行的 Agent 框架' _posts/2026-05-29-openevent-framework.md
	@grep -q 'OpenEvent: An Event-driven, Log-first Agent Framework' _posts/2026-05-29-openevent-framework-en.md
	@grep -q '事件驱动、日志先行的 Agent 框架' index.html
	@grep -q 'Event-driven, log-first Agent framework' en/index.html
	@grep -q 'og:title' _layouts/default.html
	@grep -q 'xhtml:link' sitemap.xml
	@grep -q 'Sitemap:' robots.txt
	@grep -q 'GitHub Pages' README.md

clean:
	@rm -rf _site .jekyll-cache .sass-cache
