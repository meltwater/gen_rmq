defmodule GenAMQPTest do
  use ExUnit.Case, async: false
  use GenAMQP.RabbitCase

  alias GenAmqp.Test.Assert

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_amqp_exchange"
  @out_queue "gen_amqp_out_queue"
  @in_queue "gen_amqp_in_queue"

  defmodule TestConsumer do
    @behaviour GenAMQP.Consumer

    def init(_state) do
      [
        queue: "gen_amqp_in_queue",
        exchange: "gen_amqp_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

    def consumer_tag(n) do
      "test_tag_#{n}"
    end

    def handle_message(message) do
      payload = Poison.decode!(message.payload)
      Agent.update(TestConsumer, &MapSet.put(&1, payload))
      GenAMQP.Consumer.ack(message)
    end
  end

  defmodule TestPublisher do
    @behaviour GenAMQP.Publisher

    def init(_state) do
      [
        exchange: "gen_amqp_exchange",
        uri: "amqp://guest:guest@localhost:5672",
        routing_key: "#"
      ]
    end
  end

  setup_all do
    {:ok, conn} = rmq_open(@uri)
    :ok = setup_in_queue(conn, @out_queue, @exchange)
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

      assert TestConsumer.init([]) == config[:config]
      assert TestConsumer == config[:module]
    end

    test "should receive message" do
      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: TestConsumer)
      {:ok, _} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      {:ok, _} = GenAMQP.Consumer.start_link(TestConsumer, name: :consumer)

      GenAMQP.Publisher.publish(TestPublisher, %{msg: "some message"} |> Poison.encode!())

      Assert.repeatedly(fn ->
        assert Agent.get(TestConsumer, fn set -> %{"msg" => "some message"} in set end) == true
      end)
    end

    test "should reconnect after connection failure" do
      {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: TestConsumer)
      {:ok, _} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      {:ok, consumer_pid} = GenAMQP.Consumer.start_link(TestConsumer, name: :consumer)

      state = :sys.get_state(consumer_pid)
      Process.exit(state.conn.pid, :kill)

      GenAMQP.Publisher.publish(TestPublisher, Poison.encode!(%{msg: "disconnect"}))

      Assert.repeatedly(fn ->
        assert Agent.get(TestConsumer, fn set -> %{"msg" => "disconnect"} in set end) == true
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

      assert TestPublisher.init([]) == config[:config]
      assert TestPublisher == config[:module]
    end

    test "should publish message", context do
      {:ok, _} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)
      GenAMQP.Publisher.publish(TestPublisher, %{msg: "msg"} |> Poison.encode!())

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      assert {:ok, %{"msg" => "msg"}} == get_message_from_queue(context)
    end

    test "should reconnect after connection failure", context do
      {:ok, publisher_pid} = GenAMQP.Publisher.start_link(TestPublisher, name: TestPublisher)

      state = :sys.get_state(publisher_pid)
      Process.exit(state.channel.conn.pid, :kill)

      Assert.repeatedly(fn ->
        new_state = :sys.get_state(publisher_pid)
        assert new_state.channel.conn.pid != state.channel.conn.pid
      end)

      GenAMQP.Publisher.publish(TestPublisher, Poison.encode!(%{msg: "pub_disc"}))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      assert {:ok, %{"msg" => "pub_disc"}} == get_message_from_queue(context)
    end
  end
end
