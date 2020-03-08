defmodule TestPublisher do
  defmodule Default do
    @moduledoc false
    @behaviour GenRMQ.Publisher

    def init() do
      [
        exchange: "gen_rmq_out_exchange",
        connection: "amqp://guest:guest@localhost:5672",
        app_id: :my_app_id
      ]
    end
  end

  defmodule RedeclaringExistingExchange do
    @moduledoc false
    @behaviour GenRMQ.Publisher

    def existing_exchange, do: "existing_direct_exchange"

    def init() do
      [
        exchange: existing_exchange(),
        uri: "amqp://guest:guest@localhost:5672",
        app_id: :my_app_id
      ]
    end
  end

  defmodule WithConfirmations do
    @moduledoc false
    @behaviour GenRMQ.Publisher

    def init() do
      [
        exchange: "gen_rmq_out_exchange",
        connection: "amqp://guest:guest@localhost:5672",
        app_id: :my_app_id,
        enable_confirmations: true
      ]
    end
  end
end
