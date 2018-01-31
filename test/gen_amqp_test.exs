defmodule GenAMQPTest do
  use ExUnit.Case, async: false
  use GenAMQP.RabbitCase

  alias GenAmqp.Test.Assert

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_amqp_exchange"
  @out_queue "gen_amqp_out_queue"

  defmodule TestConsumer do
    @behaviour GenAMQP.Consumer

    def init() do
      [
        queue: "gen_amqp_in_queue",
        exchange: "gen_amqp_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

    def consumer_tag() do
      "test_tag"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(TestConsumer, &MapSet.put(&1, payload))
      GenAMQP.Consumer.ack(message)
    end
  end

  defmodule TestPublisher do
    @behaviour GenAMQP.Publisher

    def init() do
      [
        exchange: "gen_amqp_exchange",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end
  end

  setup_all do
    {:ok, conn} = rmq_open(@uri)
    :ok = setup_out_queue(conn, @out_queue, @exchange)
    {:ok, rabbit_conn: conn, out_queue: @out_queue}
  end

  setup do
    purge_queues(@uri, [@out_queue])
  end

  describe "GenAMQP.Consumer" do
    test "should start new consumer" do
      {:ok, pid} = GenAMQP.Consumer.start_link(TestConsumer, name: TestConsumer)
      assert pid == Process.whereis(TestConsumer)
    end

    test "should return consumer config" do
      {:ok, config} = GenAMQP.Consumer.init(%{module: TestConsumer})

      assert TestConsumer.init() == config[:config]
    end

    test "should receive message", context do
      message = %{"msg" => "some message"}

      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: TestConsumer)
      {:ok, _} = GenAMQP.Consumer.start_link(TestConsumer, name: :consumer)
      publish_message(context[:rabbit_conn], @exchange, Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(TestConsumer, fn set -> message in set end) == true
      end)
    end

    test "should reconnect after connection failure", context do
      message = %{"msg" => "disconnect"}

      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: TestConsumer)
      {:ok, consumer_pid} = GenAMQP.Consumer.start_link(TestConsumer, name: :consumer)

      state = :sys.get_state(consumer_pid)
      Process.exit(state.conn.pid, :kill)

      publish_message(context[:rabbit_conn], @exchange, Poison.encode!(message))

      Assert.repeatedly(fn ->
        assert Agent.get(TestConsumer, fn set -> message in set end) == true
      end)
    end
  end

  describe "GenAMQP.Publisher" do
    test "should start new publisher for given module" do
      {:ok, pid} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      assert pid == Process.whereis(TestPublisher)
    end

    test "should return publisher config" do
      {:ok, config} = GenAMQP.Publisher.init(%{module: TestPublisher})

      assert TestPublisher.init() == config[:config]
    end

    test "should publish message", context do
      message = %{"msg" => "msg"}

      {:ok, _} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenAMQP.Publisher.publish(TestPublisher, Poison.encode!(%{"msg" => "msg"}))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "#" == meta[:routing_key]
    end

    test "should publish message with custom routing key", context do
      message = %{"msg" => "msg"}

      {:ok, _} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenAMQP.Publisher.publish(TestPublisher, Poison.encode!(message), "some.routing.key")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "some.routing.key" == meta[:routing_key]
    end

    test "should reconnect after connection failure", context do
      message = %{"msg" => "pub_disc"}

      {:ok, publisher_pid} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)

      state = :sys.get_state(publisher_pid)
      Process.exit(state.channel.conn.pid, :kill)

      Assert.repeatedly(fn ->
        new_state = :sys.get_state(publisher_pid)
        assert new_state.channel.conn.pid != state.channel.conn.pid
      end)

      GenAMQP.Publisher.publish(TestPublisher, Poison.encode!(message))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "#" == meta[:routing_key]
    end
  end
end
