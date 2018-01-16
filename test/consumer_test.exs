defmodule Scribe.GenConsumerTest do
  use ExUnit.Case

  defmodule Consumer do
    @behaviour GenAMQP.Consumer

    def init(_state) do
      [
        queue: "gen_consumer_test",
        exchange: "gen_consumer_exchange",
        routing_key: "gen_consumer_routing_key",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

    def consumer_tag(n) do
      "test_tag_#{n}"
    end
  end

  describe "GenConsumer" do
    test "should start new consumer for given module" do
      {:ok, pid} = GenAMQP.Consumer.start_link(Consumer, [name: Consumer])
      assert pid == Process.whereis(Consumer)
    end

    test "should return consumer config" do
      {:ok, config} = %{module: Consumer}
      |> GenAMQP.Consumer.init

      assert Consumer.init([]) == config[:config]
      assert Consumer == config[:module]
    end
  end
end
