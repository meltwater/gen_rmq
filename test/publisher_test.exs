defmodule GenAMQP.PublisherTest do
  use ExUnit.Case
  use GenAMQP.RabbitCase

  alias GenAmqp.Test.Assert

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_publisher_exchange"
  @out_queue "gen_publisher_queue"

  defmodule Publisher do
    @behaviour GenAMQP.Publisher

    def init(_state) do
      [
        exchange: "gen_publisher_exchange",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

    def publish_message(message) do
      GenServer.call(__MODULE__, {:publish, message})
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

  describe "GenPublisher" do
    test "should start new publisher for given module" do
      {:ok, pid} = GenAMQP.Publisher.start_link(Publisher, [name: Publisher])
      assert pid == Process.whereis(Publisher)
    end

    test "should return publisher config" do
      {:ok, config} = %{module: Publisher}
      |> GenAMQP.Publisher.init

      assert Publisher.init([]) == config[:config]
      assert Publisher == config[:module]
    end

    test "should publish message", context do
      {:ok, _} = GenAMQP.Publisher.start_link(Publisher, [name: Publisher])
      Publisher.publish_message(%{msg: "msg"} |> Poison.encode!)

      Assert.repeatedly(fn() -> assert out_queue_count(context) >= 1 end)
      assert {:ok, %{"msg" => "msg"}} == get_message_from_queue(context)
    end
  end
end
