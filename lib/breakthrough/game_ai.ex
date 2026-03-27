defmodule Breakthrough.GameAI do
  @moduledoc false

  alias Breakthrough.Game

  @type move :: %{from: Game.coord(), to: Game.coord()}

  @callback choose_move(Game.t(), Game.player()) :: {:ok, move()} | {:error, :no_legal_moves}
end
