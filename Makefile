.PHONY: clean code-analysis code-anaylysis-strict test docker-compose-up-up-test doc

all: build ;

clean:
	rm -rf _build deps mix.lock

code-analysis: deps
	mix credo

code-analysis-strict: deps
	mix credo --strict

deps: mix.exs
	mix deps.get
	touch deps

doc: deps
	mix docs

docker-compose-up-test:
	docker-compose -f docker-compose.yml up -d

outdated-dependencies: deps
	mix hex.outdated

test: deps docker-compose-up-test
	sleep 5;
	MIX_ENV=test mix coveralls

test_ci: deps docker-compose-up-test
	sleep 5;
	MIX_ENV=test mix coveralls.travis
