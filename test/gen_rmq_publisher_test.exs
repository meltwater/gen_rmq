defmodule GenRMQ.PublisherTest do
  use ExUnit.Case, async: false
  use GenRMQ.RabbitCase

  alias GenRMQ.Publisher
  alias GenRMQ.Test.Assert

  alias TestPublisher.Default
  alias TestPublisher.WithConfirmations

  @uri "amqp://guest:guest@localhost:5672"
  @exchange "gen_rmq_out_exchange"
  @out_queue "gen_rmq_out_queue"
  @invalid_queue "invalid_queue"

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
      {:ok, pid} = GenRMQ.Publisher.start_link(Default)
      assert Process.alive?(pid)
    end

    test "should start a new publisher registered by name" do
      {:ok, pid} = GenRMQ.Publisher.start_link(Default, name: Default)
      assert Process.whereis(Default) == pid
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
