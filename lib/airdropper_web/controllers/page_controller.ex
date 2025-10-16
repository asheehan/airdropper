defmodule AirdropperWeb.PageController do
  use AirdropperWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
