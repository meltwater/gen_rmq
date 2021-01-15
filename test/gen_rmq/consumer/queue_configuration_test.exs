defmodule GenRMQ.Consumer.QueueConfigurationTest do
  use ExUnit.Case, async: true
  alias GenRMQ.Consumer.QueueConfiguration

  test "queue setup without arguments returns default configuration" do
    name = "some_queue_name"

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: true,
        name: "#{name}_error",
        exchange: ".deadletter",
        routing_key: "#"
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-exchange", :longstr, ".deadletter"}
        ],
        durable: true
      ]
    }

    qc = QueueConfiguration.setup(name, [])

    assert expected_conf == qc
  end

  test "queue setup with basic arguments returns correct configuration" do
    name = "some_queue_name"

    config = [
      queue: name,
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672"
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: true,
        name: "#{name}_error",
        exchange: "#{config[:exchange]}.deadletter",
        routing_key: "#"
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-exchange", :longstr, "#{config[:exchange]}.deadletter"}
        ],
        durable: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "queue setup without any queue options returns correct configuration" do
    name = "some_queue_name"

    config = [
      queue: name,
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672"
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: true,
        name: "#{name}_error",
        exchange: "#{config[:exchange]}.deadletter",
        routing_key: "#"
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-exchange", :longstr, "#{config[:exchange]}.deadletter"}
        ],
        durable: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "queue setup with queue_options returns correct configuration" do
    name = "some_queue_name"

    config = [
      queue: name,
      queue_options: [
        durable: false,
        auto_delete: true,
        passive: true,
        no_wait: true,
        arguments: [
          {"x-queue-type", :longstr, "quorum"},
          {"x-expires", :long, 42},
          {"x-max-priority", :long, 10}
        ]
      ],
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672"
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: true,
        name: "#{name}_error",
        exchange: "#{config[:exchange]}.deadletter",
        routing_key: "#"
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-exchange", :longstr, "#{config[:exchange]}.deadletter"},
          {"x-queue-type", :longstr, "quorum"},
          {"x-expires", :long, 42},
          {"x-max-priority", :long, 10}
        ],
        durable: false,
        auto_delete: true,
        passive: true,
        no_wait: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "should not create dead letter queue configuration" do
    name = "some_queue_name"

    config = [
      deadletter: false
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: false,
        name: "#{name}_error",
        exchange: ".deadletter",
        routing_key: "#"
      ],
      name: name,
      options: [
        durable: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "queue setup with defined dead letter keywords returns correct configuration " do
    name = "some_queue_name"

    config = [
      deadletter: true,
      deadletter_queue: "deadletter",
      deadletter_exchange: "deadletter_exchange",
      deadletter_routing_key: "rk"
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          durable: true
        ],
        create: true,
        name: config[:deadletter_queue],
        exchange: config[:deadletter_exchange],
        routing_key: config[:deadletter_routing_key]
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-routing-key", :longstr, config[:deadletter_routing_key]},
          {"x-dead-letter-exchange", :longstr, config[:deadletter_exchange]}
        ],
        durable: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "queue setup with dead letter queue_options returns correct configuration" do
    name = "some_queue_name"

    config = [
      queue: name,
      queue_options: [
        durable: true,
        auto_delete: true,
        passive: true,
        no_wait: true,
        arguments: [
          {"x-queue-type", :longstr, "quorum"},
          {"x-expires", :long, 42},
          {"x-max-priority", :long, 64}
        ]
      ],
      deadletter_queue_options: [
        durable: false,
        auto_delete: true,
        passive: false,
        no_wait: false,
        arguments: [
          {"x-queue-type", :longstr, "quorum"},
          {"x-expires", :long, 42},
          {"x-max-priority", :long, 64}
        ]
      ],
      deadletter_routing_key: "rk",
      exchange: "example_exchange",
      routing_key: "routing_key.#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672"
    ]

    expected_conf = %{
      dead_letter: [
        options: [
          arguments: [
            {"x-queue-type", :longstr, "quorum"},
            {"x-expires", :long, 42},
            {"x-max-priority", :long, 64}
          ],
          durable: false,
          auto_delete: true,
          passive: false,
          no_wait: false
        ],
        create: true,
        name: "#{name}_error",
        exchange: "#{config[:exchange]}.deadletter",
        routing_key: config[:deadletter_routing_key]
      ],
      name: name,
      options: [
        arguments: [
          {"x-dead-letter-routing-key", :longstr, config[:deadletter_routing_key]},
          {"x-dead-letter-exchange", :longstr, "#{config[:exchange]}.deadletter"},
          {"x-queue-type", :longstr, "quorum"},
          {"x-expires", :long, 42},
          {"x-max-priority", :long, 64}
        ],
        durable: true,
        auto_delete: true,
        passive: true,
        no_wait: true
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end

  test "queue setup with x-max-priority over 255 is set to 255" do
    name = "some_queue_name"

    config = [
      deadletter: false,
      queue_options: [
        arguments: [
          {"x-max-priority", :long, 1000}
        ]
      ]
    ]

    expected_conf = %{
      name: "some_queue_name",
      options: [
        arguments: [
          {"x-max-priority", :long, 255}
        ],
        durable: true
      ],
      dead_letter: [
        options: [durable: true],
        create: false,
        name: "some_queue_name_error",
        exchange: ".deadletter",
        routing_key: "#"
      ]
    }

    qc = QueueConfiguration.setup(name, config)

    assert expected_conf == qc
  end
end
