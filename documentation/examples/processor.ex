defmodule ExampleProcessor do
  @moduledoc """
  Example GenRMQ.Processor implementation

  Sample usage:
  ```
  iex -S mix
  iex(1)> ExampleProcessor.process(%GenRMQ.Message{payload: "Hello", attributes: [], state: %{}})
  Received message: %GenRMQ.Message{attributes: [], payload: "Hello", state: %{}}
  iex(2)> ExampleProcessor.process(%GenRMQ.Message{payload: "error", attributes: [], state: %{}})
  ** (RuntimeError) Exception triggered by message
    (gen_rmq) examples/processor.ex:18: ExampleProcessor.process/1
  ```
  """

  @behaviour GenRMQ.Processor

  def process(%GenRMQ.Message{payload: "error"}), do: raise("Exception triggered by message")

  def process(%GenRMQ.Message{} = message) do
    IO.puts("Received message: #{inspect(message)}")
    :ok
  end
end
