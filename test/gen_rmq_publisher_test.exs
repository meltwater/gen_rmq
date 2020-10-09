defmodule GenRMQ.PublisherTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Publisher
  alias GenRMQ.Test.Assert

  alias TestPublisher.{
    Default,
    RedeclaringExistingExchange,
    WithConfirmations,
    WithDefaultExchange
  }

  @connection "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_out_exchange"
  @out_queue "gen_rmq_out_queue"
  @invalid_queue "invalid_queue"

  setup_all do
    {:ok, conn} = rmq_open(@connection)
    :ok = setup_out_queue(conn, @out_queue, @exchange)
    {:ok, rabbit_conn: conn, out_queue: @out_queue}
  end

  setup do
    purge_queues(@connection, [@out_queue])
  end

  describe "start_link/2" do
    test "should start a new publisher" do
      {:ok, pid} = GenRMQ.Publisher.start_link(Default)
      assert Process.alive?(pid)
    end

    test "should start a new publisher registered by name" do
      {:ok, pid} = GenRMQ.Publisher.start_link(Default, name: Default)
      assert Process.whereis(Default) == pid
    end

    test "should fail when try to redeclare an exchange with different type", %{rabbit_conn: conn} do
      Process.flag(:trap_exit, true)
      {:ok, chan} = open_channel(conn)

      GenRMQ.Binding.declare_exchange(chan, {:direct, RedeclaringExistingExchange.existing_exchange()})
      {:ok, pid} = GenRMQ.Publisher.start_link(RedeclaringExistingExchange, name: RedeclaringExistingExchange)

      assert_receive {:EXIT, ^pid, {{:shutdown, {:server_initiated_close, _, _}}, _}}
    end
  end

  describe "TestPublisher.Default" do
    setup do
      with_test_publisher(Default)
    end

    test "should publish message", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(%{"msg" => "msg"}))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with custom routing key", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message), "some.routing.key")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert "some.routing.key" == meta[:routing_key]
      assert [] == meta[:headers]
    end

    test "should publish message with headers", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message), "some.routing.key", header1: "value")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, received_message, meta} = get_message_from_queue(context)

      assert message == received_message
      assert [{"header1", :longstr, "value"}] == meta[:headers]
    end

    test "should override standard metadata fields from headers", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}

      :ok =
        GenRMQ.Publisher.publish(
          publisher_pid,
          Jason.encode!(message),
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

    test "should override default metadata fields", %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}
      sent_metadata = [app_id: "custom_id", content_type: "text/plain", timestamp: 1]
      :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message), "some.routing.key", sent_metadata)

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, _received_message, received_metadata} = get_message_from_queue(context)

      assert received_metadata[:app_id] == sent_metadata[:app_id]
      assert received_metadata[:content_type] == sent_metadata[:content_type]
      assert received_metadata[:timestamp] == sent_metadata[:timestamp]
    end

    test "should publish a message with priority", %{publisher: publisher_pid} = context do
      message = %{"msg" => "with prio"}

      :ok =
        GenRMQ.Publisher.publish(
          publisher_pid,
          Jason.encode!(message),
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

      :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))

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

  describe "consumer_count/2" do
    setup do
      with_test_publisher(Default)
    end

    test "should return the correct number of consumers when a valid queue is provided", %{publisher: publisher_pid} do
      assert 0 == GenRMQ.Publisher.consumer_count(publisher_pid, @out_queue)
    end

    test "should raise an error when an invalid queue is provided", %{publisher: publisher_pid} do
      catch_exit do
        GenRMQ.Publisher.consumer_count(publisher_pid, @invalid_queue)
      end

      assert_receive {:EXIT, ^publisher_pid, _error_details}
    end
  end

  describe "empty?/2" do
    setup do
      with_test_publisher(Default)
    end

    test "should return true if the provided queue is empty", %{publisher: publisher_pid} do
      assert true == GenRMQ.Publisher.empty?(publisher_pid, @out_queue)
    end

    test "should return false if the provided queue is not empty", %{publisher: publisher_pid} = context do
      messages = generate_messages(5)

      Enum.each(messages, fn message ->
        :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))
      end)

      Assert.repeatedly(fn -> assert out_queue_count(context) == 5 end)
      assert false == GenRMQ.Publisher.empty?(publisher_pid, @out_queue)
    end

    test "should raise an error if the provided queue is invalid", %{publisher: publisher_pid} do
      catch_exit do
        GenRMQ.Publisher.empty?(publisher_pid, @invalid_queue)
      end

      assert_receive {:EXIT, ^publisher_pid, _error_details}
    end
  end

  describe "message_count/2" do
    setup do
      with_test_publisher(Default)
    end

    test "should return the correct number of messages when a valid empty queue is provided", %{
      publisher: publisher_pid
    } do
      assert 0 == GenRMQ.Publisher.message_count(publisher_pid, @out_queue)
    end

    test "should return the correct number of messages when a valid queue is provided",
         %{publisher: publisher_pid} = context do
      messages = generate_messages(5)

      Enum.each(messages, fn message ->
        :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))
      end)

      Assert.repeatedly(fn -> assert out_queue_count(context) == 5 end)
      assert length(messages) == GenRMQ.Publisher.message_count(publisher_pid, @out_queue)
    end

    test "should raise an error when an invalid queue is provided", %{publisher: publisher_pid} do
      catch_exit do
        GenRMQ.Publisher.message_count(publisher_pid, @invalid_queue)
      end

      assert_receive {:EXIT, ^publisher_pid, _error_details}
    end
  end

  describe "purge/2" do
    setup do
      with_test_publisher(Default)
    end

    test "should return an ok tuple when a valid empty queue is successfully purged", %{publisher: publisher_pid} do
      assert {:ok, %{message_count: 0}} == GenRMQ.Publisher.purge(publisher_pid, @out_queue)
    end

    test "should return an ok tuple when a valid queue with messages is successfully purged",
         %{publisher: publisher_pid} = context do
      messages = generate_messages(5)

      Enum.each(messages, fn message ->
        :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))
      end)

      Assert.repeatedly(fn -> assert out_queue_count(context) == 5 end)
      assert {:ok, %{message_count: 5}} == GenRMQ.Publisher.purge(publisher_pid, @out_queue)
      assert {:ok, %{message_count: 0}} == GenRMQ.Publisher.purge(publisher_pid, @out_queue)
    end

    test "should raise an error when an invalid queue is provided", %{publisher: publisher_pid} do
      catch_exit do
        GenRMQ.Publisher.purge(publisher_pid, @invalid_queue)
      end

      assert_receive {:EXIT, ^publisher_pid, _error_details}
    end
  end

  describe "status/2" do
    setup do
      with_test_publisher(Default)
    end

    test "should return an ok tuple when a valid empty queue is successfully purged", %{publisher: publisher_pid} do
      assert {:ok, %{message_count: 0, consumer_count: 0, queue: "gen_rmq_out_queue"}} ==
               GenRMQ.Publisher.status(publisher_pid, @out_queue)
    end

    test "should return an ok tuple when a valid queue with messages is successfully purged",
         %{publisher: publisher_pid} = context do
      messages = generate_messages(5)

      Enum.each(messages, fn message ->
        :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))
      end)

      Assert.repeatedly(fn -> assert out_queue_count(context) == 5 end)

      assert {:ok, %{message_count: 5, consumer_count: 0, queue: "gen_rmq_out_queue"}} ==
               GenRMQ.Publisher.status(publisher_pid, @out_queue)
    end

    test "should raise an error when an invalid queue is provided", %{publisher: publisher_pid} do
      catch_exit do
        GenRMQ.Publisher.status(publisher_pid, @invalid_queue)
      end

      assert_receive {:EXIT, ^publisher_pid, _error_details}
    end
  end

  describe "TestPublisher.WithConfirmations" do
    setup do
      with_test_publisher(WithConfirmations)
    end

    test "should publish a message and wait for a confirmation", %{publisher: publisher_pid} = context do
      message = %{"msg" => "with confirmation"}
      publish_result = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message), "some.routing.key")

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      assert match?({:ok, ^message, _}, get_message_from_queue(context))
      assert {:ok, :confirmed} == publish_result
    end
  end

  describe "TestPublisher.WithDefaultExchange" do
    setup do
      with_test_publisher(WithDefaultExchange)
    end

    test "should publish a message to a default exchange", %{publisher: publisher_pid} = context do
      message = %{"msg" => "with confirmation"}
      # https://www.rabbitmq.com/tutorials/amqp-concepts.html#exchange-default
      # all queues are bound to the default exchange with a queue name as a binding key
      routing_key = context.out_queue
      publish_result = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message), routing_key)

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      assert match?({:ok, ^message, _}, get_message_from_queue(context))
      assert {:ok, :confirmed} == publish_result
    end
  end

  describe "Telemetry events" do
    setup :attach_telemetry_handlers

    setup do
      with_test_publisher(Default)
    end

    test "should be emitted when the publisher start and completes setup" do
      assert_receive {:telemetry_event, [:gen_rmq, :publisher, :connection, :start], %{system_time: _}, %{exchange: _}}

      assert_receive {:telemetry_event, [:gen_rmq, :publisher, :connection, :stop], %{duration: _}, %{exchange: _}}
    end

    test "should be emitted when the publisher starts and completes the publishing of a message",
         %{publisher: publisher_pid} = context do
      message = %{"msg" => "msg"}
      :ok = GenRMQ.Publisher.publish(publisher_pid, Jason.encode!(message))

      Assert.repeatedly(fn -> assert out_queue_count(context) >= 1 end)
      {:ok, _received_message, _meta} = get_message_from_queue(context)

      assert_receive {:telemetry_event, [:gen_rmq, :publisher, :message, :start], %{system_time: _},
                      %{exchange: _, message: _}}

      assert_receive {:telemetry_event, [:gen_rmq, :publisher, :message, :stop], %{duration: _},
                      %{exchange: _, message: _}}
    end
  end

  defp attach_telemetry_handlers(%{test: test}) do
    self = self()

    :ok =
      :telemetry.attach_many(
        "#{test}",
        [
          [:gen_rmq, :publisher, :connection, :start],
          [:gen_rmq, :publisher, :connection, :stop],
          [:gen_rmq, :publisher, :message, :start],
          [:gen_rmq, :publisher, :message, :stop]
        ],
        fn name, measurements, metadata, _ ->
          send(self, {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )
  end

  defp with_test_publisher(module) do
    Process.flag(:trap_exit, true)
    {:ok, publisher_pid} = Publisher.start_link(module)

    state = :sys.get_state(publisher_pid)

    on_exit(fn -> Process.exit(publisher_pid, :normal) end)
    {:ok, %{publisher: publisher_pid, state: state}}
  end

  defp generate_messages(num_messages) do
    1..num_messages
    |> Enum.map(fn num ->
      %{"message_#{num}" => "message_#{num}"}
    end)
  end
end
