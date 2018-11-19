defmodule GenRMQ.PublisherTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Publisher
  alias GenRMQ.Test.Assert

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_out_exchange"
  @out_queue "gen_rmq_out_queue"

  defmodule TestPublisher do
    @behaviour GenRMQ.Publisher

    def init() do
      [
        exchange: "gen_rmq_out_exchange",
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

  describe "start_link/2" do
    test "should start a new publisher" do
      {:ok, pid} = GenRMQ.Publisher.start_link(TestPublisher)
      assert Process.alive?(pid)
    end

    test "should start a new publisher registered by name" do
      {:ok, pid} = GenRMQ.Publisher.start_link(TestPublisher, name: TestPublisher)
      assert Process.whereis(TestPublisher) == pid
    end
  end

  describe "GenRMQ.Publisher" do
    setup do
      with_test_publisher()
    end

    test "should publish message", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      GenRMQ.Publisher.publish(publisher_pid, Poison.encode!(%{"msg" => "msg"}))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with custom routing key", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      GenRMQ.Publisher.publish(publisher_pid, Poison.encode!(message), "some.routing.key")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "some.routing.key" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with headers", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      GenRMQ.Publisher.publish(publisher_pid, Poison.encode!(message), "some.routing.key", header1: "value")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert [{"header1", :longstr, "value"}] == meta[:headers]
    end

    test "should override standard metadata fields from headers", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      GenRMQ.Publisher.publish(
        publisher_pid,
        Poison.encode!(message),
        "some.routing.key",
        message_id: "message_id_1",
        correlation_id: "correlation_id_1",
        header1: "value"
      )

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert meta[:message_id] == "message_id_1"
      assert meta[:correlation_id] == "correlation_id_1"
      refute meta[:header1]

      assert [{"header1", :longstr, "value"}] == meta[:headers]
    end

    test "should publish a message with priority", %{publisher: publisher_pid} = context do
      message = %{"msg" => "with prio"}

      GenRMQ.Publisher.publish(
        publisher_pid,
        Poison.encode!(message),
        "some.routing.key",
        priority: 100
      )

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert meta[:priority] == 100
    end

    test "should reconnect after connection failure", %{publisher: publisher_pid, state: state} = context do
      message = %{"msg" => "pub_disc"}

      Process.exit(state.channel.conn.pid, :kill)

      Assert.repeatedly(fn ->
        new_state = :sys.get_state(publisher_pid)
        assert new_state.channel.conn.pid != state.channel.conn.pid
      end)

      GenRMQ.Publisher.publish(publisher_pid, Poison.encode!(message))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should close connection and channel on termination", %{publisher: publisher_pid, state: state} do
      Process.exit(publisher_pid, :shutdown)

      Assert.repeatedly(fn ->
        assert Process.alive?(state.conn.pid) == false
        assert Process.alive?(state.channel.pid) == false
      end)
    end
  end

  defp with_test_publisher(module \\ TestPublisher) do
    Process.flag(:trap_exit, true)
    {:ok, publisher_pid} = Publisher.start_link(module)

    state = :sys.get_state(publisher_pid)

    on_exit(fn -> Process.exit(publisher_pid, :normal) end)
    {:ok, %{publisher: publisher_pid, state: state}}
  end
end
