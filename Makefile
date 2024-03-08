.PHONY: server
server:
	bundle exec jekyll server --livereload --draft

.PHONY: fmt
fmt:
	yarn run prettier --write '**/**.{yml,md,html}'

.PHONY: lint
lint:
	yarn textlint .
