defmodule GenRMQ.Consumer.QueueConfigurationTest do
  use ExUnit.Case, async: true
  alias GenRMQ.Consumer.QueueConfiguration

  test "may be built with just a queue name" do
    qc = QueueConfiguration.new("some_queue_name")
    assert "some_queue_name" == QueueConfiguration.name(qc)
  end

  test "durable should default to true" do
    qc = QueueConfiguration.new("some_queue_name")
    assert QueueConfiguration.durable(qc)
  end

  test "may be built with all options" do
    name = "some_queue_name"
    ttl = 5000
    durable = false
    max_priority = 200

    qc =
      QueueConfiguration.new(
        name,
        durable,
        ttl,
        max_priority
      )

    assert name == QueueConfiguration.name(qc)
    assert durable == QueueConfiguration.durable(qc)
    assert ttl == QueueConfiguration.ttl(qc)
    assert max_priority == QueueConfiguration.max_priority(qc)
  end

  test "sets max_priority values that are too large to the max" do
    qc = QueueConfiguration.new("some_queue_name", max_priority: 500)
    assert 255 == QueueConfiguration.max_priority(qc)
  end

  test "builds empty arguments when neither ttl or max_priority are provided" do
    qc = QueueConfiguration.new("some_queue_name")
    assert [] == QueueConfiguration.build_queue_arguments(qc, [])
  end

  test "builds correct arguments when ttl and max_priority are provided" do
    ttl = 5000
    max_priority = 5

    qc =
      QueueConfiguration.new(
        "some_queue_name",
        ttl: ttl,
        max_priority: max_priority
      )

    assert [{"x-expires", :long, ttl}, {"x-max-priority", :long, max_priority}] ==
             QueueConfiguration.build_queue_arguments(qc, [])
  end
end
