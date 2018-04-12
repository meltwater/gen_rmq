defmodule GenRMQ.PublisherTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Test.Assert

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_exchange"
  @out_queue "gen_rmq_out_queue"

  defmodule TestPublisher do
    @behaviour GenRMQ.Publisher

    def init() do
      [
        exchange: "gen_rmq_exchange",
        uri: "amqp://guest:guest@localhost:5672",
        app_id: :my_app_id
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

  describe "GenRMQ.Publisher" do
    test "should start new publisher for given module" do
      {:ok, pid} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)
      assert pid == Process.whereis(TestPublisher)
    end

    test "should return publisher config" do
      {:ok, config} = GenRMQ.Publisher.init(%{module: TestPublisher})

      assert TestPublisher.init() == config[:config]
    end

    test "should publish message", context do
      message = %{"msg" => "msg"}

      {:ok, _} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenRMQ.Publisher.publish(TestPublisher, Poison.encode!(%{"msg" => "msg"}))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with custom routing key", context do
      message = %{"msg" => "msg"}

      {:ok, _} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenRMQ.Publisher.publish(TestPublisher, Poison.encode!(message), "some.routing.key")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "some.routing.key" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with headers", context do
      message = %{"msg" => "msg"}

      {:ok, _} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenRMQ.Publisher.publish(TestPublisher, Poison.encode!(message), "some.routing.key", header1: "value")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert [{"header1", :longstr, "value"}] == meta[:headers]
    end

    test "should reconnect after connection failure", context do
      message = %{"msg" => "pub_disc"}

      {:ok, publisher_pid} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)

      state = :sys.get_state(publisher_pid)
      Process.exit(state.channel.conn.pid, :kill)

      Assert.repeatedly(fn ->
        new_state = :sys.get_state(publisher_pid)
        assert new_state.channel.conn.pid != state.channel.conn.pid
      end)

      GenRMQ.Publisher.publish(TestPublisher, Poison.encode!(message))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "" == meta[:routing_key]
      assert [] == meta[:headers]
    end
  end
end
