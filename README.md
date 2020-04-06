[![Build Status](https://travis-ci.org/meltwater/gen_rmq.svg?branch=master)](https://travis-ci.org/meltwater/gen_rmq)
[![Hex Version](http://img.shields.io/hexpm/v/gen_rmq.svg)](https://hex.pm/packages/gen_rmq)
[![Coverage Status](https://coveralls.io/repos/github/meltwater/gen_rmq/badge.svg?branch=master)](https://coveralls.io/github/meltwater/gen_rmq?branch=master)
[![Hex.pm Download Total](https://img.shields.io/hexpm/dt/gen_rmq.svg?style=flat-square)](https://hex.pm/packages/gen_rmq)
[![Dependabot Status](https://api.dependabot.com/badges/status?host=github&repo=meltwater/gen_rmq)](https://dependabot.com)

# GenRMQ

GenRMQ is a set of [behaviours][behaviours] meant to be used to create RabbitMQ consumers and publishers.

Internally it is using the [AMQP][amqp] elixir RabbitMQ client. The idea is to reduce boilerplate consumer / publisher code, which usually includes:

- creating connection / channel and keeping it in a state
- creating and binding queue
- handling reconnections / consumer cancellations

GenRMQ provides the following functionality:

- `GenRMQ.Consumer` - a behaviour for implementing RabbitMQ consumers ([example][example_consumer])
- `GenRMQ.Publisher` - a behaviour for implementing RabbitMQ publishers ([example][example_publisher])
- `GenRMQ.Processor` - a behaviour for implementing RabbitMQ message processors (this is useful to separate out business logic from your consumer) ([example][example_processor])
- `GenRMQ.RabbitCase` - test utilities for RabbitMQ ([example][example_rabbit_case])

## Installation

```elixir
def deps do
  [{:gen_rmq, "~> 2.5.0"}]
end
```

## Migrations

If you were a very early adopter of gen_rmq (before `v1.0.0`), please check [how to migrate to gen_rmq `1.0.0`][migrating_to_100].

## Examples

More thorough examples for using `GenRMQ.Consumer`, `GenRMQ.Publisher`, and `GenRMQ.Processor`
can be found under [documentation][examples].

### Consumer

```elixir
defmodule Consumer do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      queue: "gen_rmq_in_queue",
      exchange: "gen_rmq_exchange",
      routing_key: "#",
      prefetch_count: "10",
      connection: "amqp://guest:guest@localhost:5672",
      retry_delay_function: fn attempt -> :timer.sleep(2000 * attempt) end
    ]
  end

  def consumer_tag() do
    "test_tag"
  end

  def handle_message(message) do
    ...
  end
end
```

```elixir
GenRMQ.Consumer.start_link(Consumer, name: Consumer)
```

This will result in:

- durable `gen_rmq_exchange.deadletter` exchange created or redeclared
- durable `gen_rmq_in_queue_error` queue created or redeclared. It will be bound to `gen_rmq_exchange.deadletter`
- durable topic `gen_rmq_exchange` exchange created or redeclared
- durable `gen_rmq_in_queue` queue created or redeclared. It will be bound to `gen_rmq_exchange` exchange and has a deadletter exchange set to `gen_rmq_exchange.deadletter`
- every `handle_message` callback will executed in separate process. This can be disabled by setting `concurrency: false` in `init` callback
- on failed rabbitmq connection it will wait for a bit and then reconnect

There are many options to control the consumer setup details, please check the `c:GenRMQ.Consumer.init/0` [docs][consumer_doc] for all available settings.

### Publisher

```elixir
defmodule Publisher do
  @behaviour GenRMQ.Publisher

  def init() do
    [
      exchange: "gen_rmq_exchange",
      connection: "amqp://guest:guest@localhost:5672"
    ]
  end
end
```

```elixir
GenRMQ.Publisher.start_link(Publisher, name: Publisher)
GenRMQ.Publisher.publish(Publisher, Jason.encode!(%{msg: "msg"}))
```

## Documentation

### Examples

1. [Consumer][example_consumer]
2. [Publisher][example_publisher]
3. [Processor][example_processor]

### Guides

1. [Basic consumer setup][guide_consumer_basic_setup]
2. [Consumer with custom deadletter configuration][guide_consumer_with_custom_deadletter_configuration]
3. [Consumer with custom exchange type][guide_consumer_with_custom_exchange_type]
4. [Consumer with custom queue configuration][guide_consumer_with_custom_queue_configuration]
5. [Consumer without deadletter configuration][without_deadletter_configuration]
6. [Consumer with quorum queues][with_quorum_queue_type]

### Metrics

1. [Consumer Telemetry events][consumer_telemetry_events]
2. [Publisher Telemetry events][publisher_telemetry_events]

## Running Tests

You need [docker-compose][docker_compose] installed.

```bash
$ make test
```

## How to Contribute

We happily accept contributions as [GitHub PRs][github_prs] or bug reports, comments/suggestions or usage questions by creating a [GitHub issue][gen_rmq_issues].

Are you using `gen_rmq` in production? Please let us know, we are curious to learn about your experiences!

## Maintainers

* Mateusz ([@mkorszun](https://github.com/mkorszun))

The maintainers are responsible for the general project oversight, and empowering further trusted committers (see below).

The maintainers are the ones that create new releases of gen_rmq.

## Trusted Committers

* Joel ([@vorce](https://github.com/vorce))
* Sebastian ([@spier](https://github.com/spier))

**Trusted Committers** are members of our community who we have explicitly added to our GitHub repository.

Trusted Committers have elevated rights, allowing them to send in changes directly to branches and to approve Pull Requests.

For details see [TRUSTED-COMMITTERS.md][trusted_commiters].

*Note:* Maintainers as well as Trusted Committers are listed in [.github/CODEOWNERS][code_owners] in order to automatically assign PR reviews to them.

## License

The [MIT License](LICENSE).

Copyright (c) 2018 - 2020 Meltwater Inc. [underthehood.meltwater.com][underthehood]

[behaviours]: https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours
[amqp]: https://github.com/pma/amqp
[migrating_to_100]: https://github.com/meltwater/gen_rmq/wiki/Migrations#0---100
[consumer_doc]: https://github.com/meltwater/gen_rmq/blob/master/lib/consumer.ex
[docker_compose]: https://docs.docker.com/compose/
[github_prs]: https://help.github.com/articles/about-pull-requests/
[gen_rmq_issues]: https://github.com/meltwater/gen_rmq/issues
[priority_queues]: https://www.rabbitmq.com/priority.html
[underthehood]: http://underthehood.meltwater.com/

[examples]: https://github.com/meltwater/gen_rmq/blob/master/documentation/examples
[example_consumer]: https://github.com/meltwater/gen_rmq/blob/master/documentation/examples/consumer.ex
[example_publisher]: https://github.com/meltwater/gen_rmq/blob/master/documentation/examples/publisher.ex
[example_processor]: https://github.com/meltwater/gen_rmq/blob/master/documentation/examples/processor.ex
[example_rabbit_case]: https://github.com/meltwater/gen_rmq/blob/master/test/gen_rmq_publisher_test.exs

[guide_consumer_basic_setup]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/basic_setup.md
[guide_consumer_with_custom_deadletter_configuration]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/with_custom_deadletter_configuration.md
[guide_consumer_with_custom_exchange_type]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/with_custom_exchange_type.md
[guide_consumer_with_custom_queue_configuration]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/with_custom_queue_configuration.md
[without_deadletter_configuration]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/without_deadletter_configuration.md
[with_quorum_queue_type]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/with_quorum_queue_type.md

[consumer_telemetry_events]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/consumer/telemetry_events.md
[publisher_telemetry_events]: https://github.com/meltwater/gen_rmq/blob/master/documentation/guides/publisher/telemetry_events.md

[trusted_commiters]: https://github.com/meltwater/gen_rmq/blob/master/TRUSTED-COMMITTERS.md
[code_owners]: https://github.com/meltwater/gen_rmq/blob/master/.github/CODEOWNERS