defmodule StreamingProxyTestWeb.PageController do
  use StreamingProxyTestWeb, :controller

  def index(conn, _params) do
    host = 'localhost'
    port = 8080
    query = '/'

    {:ok, pid} = :gun.open(host, port)
    monitor_ref = Process.monitor(pid)

    {:ok, _protocol} = :gun.await_up(pid)
    ref = :gun.get(pid, query)

    receive do
      {:gun_response, ^pid, ^ref, :fin, 200, headers} ->
        conn = conn
        |> put_resp_headers(headers)
        |> send_resp(200, "")
      {:gun_response, ^pid, ^ref, :nofin, status, headers} ->
        conn = conn
        |> put_resp_headers(headers)
        |> send_chunked(status)

        async_response(conn, pid, ref, monitor_ref);
      {:gun_response, ^pid, ^ref, :fin, _status, _headers} ->
        conn
      {'DOWN', ^monitor_ref, :process, ^pid, _reason} ->
        conn
    end
  end

  defp async_response(conn, pid, ref, monitor_ref) do
    receive do
      {:gun_data, ^pid, ^ref, :fin, data} ->
        case chunk(conn, data) do
          {:ok, conn} ->
            conn
          {:error, _reason} ->
            conn
        end
      {:gun_data, ^pid, ^ref, :nofin, data} ->
        case chunk(conn, data) do
          {:ok, conn} ->
            async_response(conn, pid, ref, monitor_ref)
          {:error, _reason} ->
            conn
        end
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        conn
    end
  end

  defp put_resp_headers(conn, resp_headers) do
    resp_headers = to_elixir_headers(resp_headers)

    merge_resp_headers(conn, resp_headers)
  end

  defp to_elixir_headers(gun_headers) do
    Enum.map gun_headers, fn {k, v} ->
      k = to_string(k) |> String.downcase
      v = to_string(v)

      {k, v}
    end
  end
end
